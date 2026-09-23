#!/usr/bin/env python3
"""Read-only comparison with declared schema defaults, not a JSON Schema validator."""

import argparse
import json
import math
from pathlib import Path
import sys
from urllib.parse import unquote


MISSING = object()
STATUSES = ("overridden", "pinned", "undeclared", "unknown")


def equal(left, right):
    """JSON equality: numbers compare numerically, booleans are not numbers."""
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(equal(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(equal(a, b) for a, b in zip(left, right))
    return left == right


def resolve(node, root, seen=()):
    if node is False:
        return {}, "schema disallows this value"
    if not isinstance(node, dict):
        return {}, None
    if "$ref" not in node:
        return node, None
    ref = node["$ref"]
    if not isinstance(ref, str) or not ref.startswith("#/"):
        return node, "unsupported reference"
    if ref in seen:
        return node, "cyclic reference"
    target = root
    try:
        for part in unquote(ref[2:]).split("/"):
            key = part.replace("~1", "/").replace("~0", "~")
            target = target[int(key)] if isinstance(target, list) else target[key]
    except (KeyError, IndexError, TypeError, ValueError):
        return node, "unresolved reference"
    target, problem = resolve(target, root, seen + (ref,))
    merged = dict(target)
    for key, value in node.items():
        if key == "$ref":
            continue
        if key == "default" and key in merged and not equal(merged[key], value):
            problem = "conflicting reference defaults"
        if key == "properties" and key in merged and merged[key] != value:
            # Both schemas apply: do not silently discard either property definition.
            problem = "overlapping reference properties"
        merged[key] = value
    return merged, problem


def audit(schema, config):
    rows = []

    def walk(node, value, path, known=True, problem=None):
        if node is False:
            known, problem = False, "schema disallows this value"
        node, ref_problem = resolve(node, schema)
        problem = problem or ref_problem
        if ref_problem == "schema disallows this value":
            known = False
        if any(key in node for key in ("allOf", "anyOf", "oneOf", "if", "then", "else", "patternProperties", "dependentSchemas")):
            # A direct default is useful without evaluating validation branches.
            problem = problem or "conditional or composed schema not evaluated"
        props = node.get("properties", {})
        props = props if isinstance(props, dict) else {}
        if not path and not value and isinstance(value, dict):
            return
        unconstrained = known and path and not props and "additionalProperties" not in node
        if isinstance(value, dict) and value and not problem and "default" not in node and not unconstrained:
            for key in sorted(value):
                if not path and key == "$schema":
                    continue
                child_path = path + "/" + key.replace("~", "~0").replace("/", "~1")
                if key in props:
                    child, child_known = props[key], known
                else:
                    child = node.get("additionalProperties", {})
                    # Open extension points are accepted but have no declared property defaults.
                    child_known = known and (child is True or isinstance(child, dict) and "additionalProperties" in node)
                walk(child, value[key], child_path, child_known)
            return
        default = node.get("default", MISSING)
        if problem:
            # A direct default alongside oneOf etc. remains unambiguous; reference
            # errors and defaults hidden inside branches do not.
            if problem != "conditional or composed schema not evaluated":
                default = MISSING
        status = "unknown" if not known else "undeclared" if default is MISSING else "pinned" if equal(default, value) else "overridden"
        row = {"path": path or "/", "status": status, "value": value}
        if default is not MISSING:
            row["default"] = default
        if problem:
            row["note"] = problem
        rows.append(row)

    walk(schema, config, "")
    return rows


def load(path):
    def reject_constant(value):
        raise ValueError(f"non-JSON numeric constant: {value}")

    def finite_number(value):
        result = float(value)
        if not math.isfinite(result):
            raise ValueError("JSON number exceeds supported range")
        return result

    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate object key: {key}")
            result[key] = value
        return result

    with path.open(encoding="utf-8") as handle:
        value = json.load(handle, parse_constant=reject_constant, parse_float=finite_number, object_pairs_hook=unique_keys)
    if not isinstance(value, dict):
        raise ValueError("expected a JSON object")
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", type=Path, required=True)
    parser.add_argument("--config", type=Path, default=Path.home() / ".config/cmux/cmux.json")
    parser.add_argument("--pinned", action="store_true", help="show only values equal to declared defaults")
    parser.add_argument("--json", action="store_true", help="emit structured evidence")
    args = parser.parse_args(argv)
    try:
        schema, config = load(args.schema), load(args.config)
        rows = audit(schema, config)
    except (OSError, ValueError, RecursionError) as error:
        print(f"terminal-kit: error: cmux audit: {error}", file=sys.stderr)
        return 1
    counts = {status: sum(row["status"] == status for row in rows) for status in STATUSES}
    selected = [row for row in rows if not args.pinned or row["status"] == "pinned"]
    if args.json:
        print(json.dumps({"schema_version": 1, "config": str(args.config.absolute()), "schema": str(args.schema.absolute()), "counts": counts, "rows": selected}, indent=2, ensure_ascii=True))
    else:
        print(f"Config: {args.config}\nSchema: {args.schema}")
        print("Declared defaults only; not runtime settings or a schema validation.")
        print("; ".join(f"{counts[status]} {status}" for status in STATUSES))
        def display(value):
            text = json.dumps(value, ensure_ascii=True)
            return text if len(text) <= 120 else text[:117] + "..."

        for row in selected:
            default = display(row["default"]) if "default" in row else "(not declared)"
            note = f" [{row['note']}]" if "note" in row else ""
            print(f"{row['status']:10} {json.dumps(row['path'], ensure_ascii=True)}: {display(row['value'])}; default {default}{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
