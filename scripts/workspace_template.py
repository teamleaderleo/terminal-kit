#!/usr/bin/env python3
"""Save a live cmux workspace as a reusable layout template, and re-create it.

cmux already has both halves of this:

  * `cmux tree --json` emits a workspace's `layout` in the same grammar that
  * `cmux workspace create --layout <json>` accepts.

The only thing missing between them is the contents of each pane: `tree`
reports `{"pane": {"ref": "pane:3"}}`, while `create` wants
`{"pane": {"surfaces": [...]}}`. This joins the two, resolving each surface to
something that can be re-created — its type, its url for browsers, and its cwd
and command for terminals.

cwd and command are recovered from the tty, because cmux does not record what a
terminal was started with unless someone called `cmux surface resume set`. Every
surface that could not be fully resolved is listed under `unresolved` in the
saved file rather than silently dropped.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

CMUX = os.environ.get("CMUX_CLI", "cmux")
SHELLS = {"zsh", "-zsh", "bash", "-bash", "fish", "-fish", "sh", "-sh", "login"}


def _is_shell(command: str) -> bool:
    head = os.path.basename(command.split()[0]) if command.split() else ""
    return head in SHELLS or command.startswith("/usr/bin/login")


def cmux(*args: str) -> str:
    env = dict(os.environ, CMUX_QUIET="1")
    done = subprocess.run([CMUX, *args], capture_output=True, text=True, env=env)
    if done.returncode != 0:
        sys.exit(f"cmux {' '.join(args)} failed: {done.stderr.strip() or done.stdout.strip()}")
    return done.stdout


def tty_processes(tty: str) -> list[tuple[int, int, str]]:
    out = subprocess.run(
        ["ps", "-t", tty, "-o", "pid=,ppid=,command="], capture_output=True, text=True
    )
    rows = []
    for line in out.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            rows.append((int(parts[0]), int(parts[1]), parts[2].strip()))
    return rows


VOLATILE = re.compile(
    r"/var/folders/|/private/tmp/|\bT/|[0-9A-Fa-f]{32,}|AUTH_TOKEN|_PID=|--socket\b"
)


def is_volatile(command: str) -> bool:
    """True when a command only makes sense inside the session that produced it.

    Agent resume invocations carry socket paths, per-session auth tokens and an
    owner pid. Writing one into a template would leak a credential and would
    not work anywhere else, so it is reported instead of stored.
    """
    return bool(VOLATILE.search(command))


def tty_cwd(tty: str) -> str | None:
    """The shell's working directory — not the deepest process's.

    A running agent may have chdir'd into its own cache; the directory the user
    opened is the shell's.
    """
    rows = tty_processes(tty)
    shells = [pid for pid, _, command in rows if _is_shell(command)]
    for pid in reversed(shells or [pid for pid, _, _ in rows]):
        out = subprocess.run(
            ["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], capture_output=True, text=True
        )
        paths = [line[1:] for line in out.stdout.splitlines() if line.startswith("n")]
        if paths:
            return paths[0]
    return None


def tty_command(tty: str) -> str | None:
    """The foreground command, if it is not just the shell."""
    rows = tty_processes(tty)
    shells = {pid for pid, _, command in rows if _is_shell(command)}
    # The surface's command is a direct child of the shell. Anything deeper is
    # that command's own subprocess (an MCP server, a language server) and
    # would be wrong to write into a template.
    for pid, ppid, command in rows:
        if ppid in shells and not _is_shell(command):
            return command
    return None


def resume_command(ref: str) -> str | None:
    env = dict(os.environ, CMUX_QUIET="1")
    done = subprocess.run(
        [CMUX, "surface", "resume", "get", "--surface", ref, "--json"],
        capture_output=True, text=True, env=env,
    )
    if done.returncode != 0 or not done.stdout.strip().startswith("{"):
        return None
    try:
        payload = json.loads(done.stdout)
    except json.JSONDecodeError:
        return None
    argv = payload.get("argv")
    if isinstance(argv, list) and argv:
        return " ".join(argv)
    shell = payload.get("shell")
    return shell if isinstance(shell, str) and shell else None


def surface_spec(surface: dict, unresolved: list[dict]) -> dict:
    kind = surface.get("type") or "terminal"
    spec: dict = {"type": kind}
    if kind == "browser":
        url = surface.get("url")
        if url:
            spec["url"] = url
        else:
            unresolved.append({"ref": surface["ref"], "missing": "url"})
        return spec

    tty = surface.get("tty")
    missing: list[str] = []
    reason: str | None = None
    if tty:
        cwd = tty_cwd(tty)
        if cwd:
            spec["cwd"] = cwd
        else:
            missing.append("cwd")
        command = resume_command(surface["ref"]) or tty_command(tty)
        if command and is_volatile(command):
            reason = "session-scoped invocation (socket, token or pid); not portable"
            command = None
        elif command:
            spec["command"] = command
        if not command:
            missing.append("command")
    else:
        missing.append("tty")
    if missing:
        entry = {"ref": surface["ref"], "title": surface.get("title"), "missing": missing}
        if reason:
            entry["reason"] = reason
        unresolved.append(entry)
    return spec


def resolve(node: dict, panes: dict[str, dict], unresolved: list[dict]) -> dict:
    if "children" in node:
        out = {k: v for k, v in node.items() if k in ("direction", "split")}
        out["children"] = [resolve(child, panes, unresolved) for child in node["children"]]
        return out
    ref = node.get("pane", {}).get("ref")
    pane = panes.get(ref, {})
    return {
        "pane": {
            "surfaces": [surface_spec(s, unresolved) for s in pane.get("surfaces", [])]
        }
    }


def find_workspace(tree: dict, ref: str | None) -> dict:
    workspaces = [w for window in tree.get("windows", []) for w in window.get("workspaces", [])]
    if not workspaces:
        sys.exit("no workspaces reported by cmux tree")
    if ref:
        for workspace in workspaces:
            if workspace.get("ref") == ref or workspace.get("id") == ref:
                return workspace
        sys.exit(f"workspace {ref} not found")
    for workspace in workspaces:
        if workspace.get("selected") or workspace.get("active"):
            return workspace
    return workspaces[0]


def command_save(args: argparse.Namespace) -> int:
    tree = json.loads(cmux("tree", "--json", *(["--workspace", args.workspace] if args.workspace else [])))
    workspace = find_workspace(tree, args.workspace)
    panes = {pane["ref"]: pane for pane in workspace.get("panes", [])}
    unresolved: list[dict] = []
    layout = resolve(workspace["layout"], panes, unresolved)
    template = {
        "name": args.name or workspace.get("title") or "workspace",
        "layout": layout,
        "source": {
            "workspace": workspace.get("ref"),
            "title": workspace.get("title"),
            "captured": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        },
        "unresolved": unresolved,
    }
    text = json.dumps(template, indent=2)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")
        print(f"saved {args.out}")
    else:
        print(text)
    if unresolved:
        print(
            f"{len(unresolved)} surface(s) only partially resolved; see \"unresolved\"",
            file=sys.stderr,
        )
    return 0


def command_apply(args: argparse.Namespace) -> int:
    with open(args.file, encoding="utf-8") as handle:
        template = json.load(handle)
    name = args.name or template.get("name") or "workspace"
    out = cmux(
        "workspace", "create",
        "--name", name,
        "--layout", json.dumps(template["layout"]),
        *(["--focus", "true"] if args.focus else []),
    )
    print(out.strip())
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="tk template", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    save = sub.add_parser("save", help="write the current workspace out as a template")
    save.add_argument("workspace", nargs="?", help="workspace ref or id (default: the selected one)")
    save.add_argument("--out", help="file to write (default: stdout)")
    save.add_argument("--name", help="template name (default: the workspace title)")
    save.set_defaults(func=command_save)

    apply_ = sub.add_parser("apply", help="create a workspace from a saved template")
    apply_.add_argument("file")
    apply_.add_argument("--name", help="override the workspace name")
    apply_.add_argument("--focus", action="store_true", help="focus the new workspace")
    apply_.set_defaults(func=command_apply)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
