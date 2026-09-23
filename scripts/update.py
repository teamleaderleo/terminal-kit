#!/usr/bin/env python3
"""Inspect exact Git updates and retain independent source-revision recovery."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import uuid


class Failure(Exception):
    pass


def git(root, *args):
    result = subprocess.run(['git', '-C', str(root), '-c', 'core.hooksPath=/dev/null', '-c', 'merge.autoStash=false', *args],
                            text=True, capture_output=True)
    if result.returncode:
        raise Failure(result.stderr.strip() or 'Git operation failed')
    return result.stdout.strip()


def clean(root):
    if git(root, 'status', '--porcelain', '--untracked-files=no'):
        raise Failure('commit or stash tracked changes first; source recovery never discards edits')


def protect_untracked(root, target):
    """Git reset --keep can overwrite ignored files; inspect additions ourselves."""
    def paths(*args):
        result = subprocess.run(['git', '-C', str(root), *args], capture_output=True)
        if result.returncode:
            raise Failure('cannot inspect paths for source transition')
        return {os.fsdecode(item) for item in result.stdout.split(b'\0') if item}

    tracked = paths('ls-files', '-z')
    incoming = paths('ls-tree', '-r', '--name-only', '-z', target)
    for name in incoming - tracked:
        path = root / name
        # Ask the filesystem, not Git pathspec matching: macOS can alias Unicode
        # spellings that Git's literal/icase matching does not recognize. Refuse
        # ambiguous existing leaves even for otherwise safe case-only renames.
        if os.path.lexists(path):
            raise Failure(f'existing path would be overwritten or ambiguously renamed: {name}')
        for parent in path.parents:
            if parent == root:
                break
            relative = str(parent.relative_to(root))
            if os.path.lexists(parent) and (parent.is_symlink() or not parent.is_dir()) and relative not in tracked:
                raise Failure(f'untracked or ignored parent would be overwritten: {relative}')


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def save(path, value):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def read(path):
    try:
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            raise ValueError("expected an object receipt")
        return value
    except (OSError, ValueError) as error:
        raise Failure(f'cannot read update receipt {path}: {error}') from error


def identity(root):
    branch = git(root, 'symbolic-ref', '--quiet', 'HEAD')
    name = branch.removeprefix('refs/heads/')
    try:
        remote = git(root, 'config', '--get', f'branch.{name}.remote')
        merge = git(root, 'config', '--get', f'branch.{name}.merge')
    except Failure as error:
        raise Failure('update requires a configured remote branch upstream') from error
    if remote == '.' or not merge.startswith('refs/heads/'):
        raise Failure('update requires a named remote branch upstream')
    return {'root': str(root), 'branch': branch, 'remote': remote,
            'remote_url': git(root, 'remote', 'get-url', remote), 'upstream': merge,
            'base': git(root, 'rev-parse', 'HEAD')}


def changes(root, base, target):
    git(root, 'merge-base', '--is-ancestor', base, target)
    git(root, 'diff', '--check', base, target)
    return {'diff_sha256': hashlib.sha256(subprocess.check_output(
        ['git', '-C', str(root), 'diff', '--binary', '--no-ext-diff', '--no-textconv', base, target])).hexdigest(),
        'files': git(root, 'diff', '--name-status', base, target).splitlines()}


def preview(root, state):
    clean(root)
    plan = identity(root)
    git(root, 'fetch', '--no-tags', '--', plan['remote'], plan['upstream'])
    target = git(root, 'rev-parse', 'FETCH_HEAD^{commit}')
    plan.update(target=target, **changes(root, plan['base'], target))
    current = identity(root)
    if current != {key: plan[key] for key in current}:
        raise Failure('checkout changed during inspection; inspect again')
    clean(root)
    save(state / 'plan.json', {'plan': plan, 'digest': digest(plan)})
    print(f"Source update inspection\nFrom: {plan['base']}\nTo:   {target}\nRemote: {plan['remote_url']} ({plan['upstream']})")
    print('Changed paths:')
    for file in plan['files']:
        print('  ' + file)
    if not plan['files']:
        print('  (none)')
    sensitive = [line for line in plan['files'] if any(part in line for part in ('install', 'Brewfile', 'config/zsh/', 'scripts/', 'bin/'))]
    if sensitive:
        print('Includes executable/startup/tooling changes: inspect their diff before applying.')
    print(f"Review: git -C {shlex.quote(str(root))} diff {plan['base']} {target}")
    print(f"Plan: {digest(plan)}\nNo code installed or checkout files changed.")
    print(f'Apply this exact plan: tk update --apply {target}')
    print('Application runs the installer and may change host files, packages, and services.')
    print('Recovery restores source only; it cannot undo those installer effects.')


def rollback(root, receipt_path):
    receipt = read(receipt_path)
    if receipt.get('root') != str(root):
        raise Failure('recovery receipt belongs to another checkout')
    if receipt.get('state') == 'source-restored':
        raise Failure('this source revision has already been restored')
    if git(root, 'symbolic-ref', '--quiet', 'HEAD') != receipt['branch']:
        raise Failure('branch changed since application; source rollback stopped')
    if git(root, 'rev-parse', 'HEAD') != receipt['target']:
        raise Failure('HEAD changed since application; source rollback stopped')
    if git(root, 'rev-parse', receipt['previous_ref']) != receipt['base']:
        raise Failure('saved previous revision changed; source rollback stopped')
    clean(root)
    protect_untracked(root, receipt['base'])
    git(root, 'reset', '--keep', receipt['base'])
    receipt['state'] = 'source-restored'
    save(receipt_path, receipt)
    print(f"Restored SOURCE revision {receipt['base']} on the existing branch.")
    print('Host files, packages, services, and running sessions were NOT restored.')


def apply(root, state, target):
    record = read(state / 'plan.json')
    plan = record['plan']
    if not isinstance(plan, dict):
        raise Failure('invalid inspection plan; inspect again')
    if record['digest'] != digest(plan):
        raise Failure('inspection receipt changed; run tk update again')
    if target != plan['target'] or len(target) not in (40, 64) or any(c not in '0123456789abcdef' for c in target):
        raise Failure('apply requires the full exact commit from the inspection receipt')
    clean(root)
    current = identity(root)
    if any(plan.get(key) != value for key, value in current.items()):
        raise Failure('checkout, branch, remote, or HEAD changed since inspection; inspect again')
    if any(plan.get(key) != value for key, value in changes(root, plan['base'], target).items()):
        raise Failure('inspected changes no longer match the plan')
    transaction = state / ('recovery-' + uuid.uuid4().hex)
    transaction.mkdir(mode=0o700)
    shutil.copyfile(__file__, transaction / 'recover.py')
    previous_ref = 'refs/terminal-kit/updates/' + transaction.name + '/previous'
    candidate_ref = 'refs/terminal-kit/updates/' + transaction.name + '/candidate'
    git(root, 'update-ref', previous_ref, plan['base'])
    git(root, 'update-ref', candidate_ref, target)
    receipt = {**plan, 'previous_ref': previous_ref, 'candidate_ref': candidate_ref,
               'state': 'prepared', 'plan_digest': record['digest']}
    receipt_path = transaction / 'receipt.json'
    save(receipt_path, receipt)
    # Keep the printed recovery command usable even if candidate code breaks the CLI.
    command = f'python3 {shlex.quote(str(transaction / "recover.py"))} --root {shlex.quote(str(root))} rollback --receipt {shlex.quote(str(receipt_path))}'
    print(f'Source recovery receipt: {receipt_path}\nIndependent source rollback:\n{command}', flush=True)
    clean(root)
    protect_untracked(root, target)
    git(root, 'merge', '--ff-only', '--no-edit', '--no-overwrite-ignore', target)
    save(state / 'latest.json', {'receipt': str(receipt_path)})
    receipt['state'] = 'installing'
    save(receipt_path, receipt)
    clean(root)
    if git(root, 'rev-parse', 'HEAD') != target:
        raise Failure('HEAD changed before installation; use the saved source recovery command')
    try:
        result = subprocess.run(['/bin/bash', str(root / 'install.sh')]).returncode
    except KeyboardInterrupt:
        result = 130
    if result < 0:
        result = 128 - result
    receipt['installer_exit'] = result
    receipt['state'] = 'applied' if result == 0 else 'install-failed'
    save(receipt_path, receipt)
    if result:
        print('Installer failed; attempting SOURCE-only rollback.', file=sys.stderr)
        try:
            rollback(root, receipt_path)
        except Failure as error:
            print(f'Automatic source rollback stopped: {error}\nRecovery: {command}', file=sys.stderr)
        print('Installer host effects may remain. Consult ~/.config/terminal-kit-backups/ before repairing host files.', file=sys.stderr)
        return result
    print('Update installed. Previous source retained; tk rollback restores source only.')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('action', choices=('update', 'rollback'))
    parser.add_argument('--apply', metavar='FULL_SHA')
    parser.add_argument('--receipt', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    lock = None
    try:
        if not (root / '.git').exists() or Path(git(root, 'rev-parse', '--show-toplevel')).resolve() != root:
            raise Failure('update/recovery requires a valid Git checkout; use tk install for a source archive')
        state = Path(git(root, 'rev-parse', '--absolute-git-dir')) / 'terminal-kit-update'
        state.mkdir(mode=0o700, exist_ok=True)
        lock_path = state / 'lock'
        try:
            descriptor = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            raise Failure(f'an update/recovery lock exists: {lock_path}; check for a running updater before removing a stale lock')
        lock = lock_path
        with os.fdopen(descriptor, 'w') as handle:
            handle.write(str(os.getpid()) + '\n')
        if args.action == 'rollback':
            if args.apply:
                raise Failure('--apply is only valid for update')
            receipt = args.receipt or Path(read(state / 'latest.json')['receipt'])
            rollback(root, receipt)
        elif args.receipt:
            raise Failure('--receipt is only valid for source rollback')
        elif args.apply:
            return apply(root, state, args.apply)
        else:
            preview(root, state)
        return 0
    except (Failure, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'terminal-kit: update: {error}', file=sys.stderr)
        return 1
    finally:
        if lock is not None:
            lock.unlink(missing_ok=True)


if __name__ == '__main__':
    sys.exit(main())
