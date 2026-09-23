#!/usr/bin/env python3
"""Exercise update/status with real Git and a harmless installer fixture."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parents[1]


def run(*args, ok=True):
    result = subprocess.run(args, text=True, capture_output=True, env=ENV)
    if ok and result.returncode:
        raise AssertionError(f'{args}: {result.stderr}')
    return result


def git(repo, *args):
    return run('git', '-C', str(repo), *args).stdout.strip()


def invoke(repo, command, success=True):
    result = run('bash', str(repo / 'bin/terminal-kit'), command, ok=success)
    if not success:
        assert result.returncode != 0, result.stdout
        assert 'INSTALLER' not in result.stdout, result.stdout
    return result.stdout


with tempfile.TemporaryDirectory(prefix='terminal-kit-git-') as temporary:
    base = Path(temporary)
    home = base / 'home'
    home.mkdir()
    ENV = {**os.environ, 'HOME': str(home), 'GIT_CONFIG_NOSYSTEM': '1',
           'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_TERMINAL_PROMPT': '0'}
    for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR'):
        ENV.pop(key, None)
    repo = base / 'repo'
    (repo / 'bin').mkdir(parents=True)
    shutil.copy2(SOURCE / 'bin/terminal-kit', repo / 'bin/terminal-kit')
    (repo / 'install.sh').write_text("printf 'INSTALLER\\n'\n")
    git(repo, 'init', '-q')
    git(repo, 'config', 'user.name', 'Fixture')
    git(repo, 'config', 'user.email', 'fixture@example.invalid')
    git(repo, 'add', '.')
    git(repo, 'commit', '-qm', 'initial')
    remote = base / 'remote.git'
    run('git', 'clone', '-q', '--bare', str(repo), str(remote))
    git(repo, 'remote', 'add', 'origin', str(remote))
    git(repo, 'fetch', '-q', 'origin')
    branch = git(repo, 'branch', '--show-current')
    git(repo, 'branch', '--set-upstream-to=origin/' + branch)
    assert 'working tree: clean' in invoke(repo, 'status')
    linked = base / 'linked'
    git(repo, 'worktree', 'add', '-qb', 'linked-test', str(linked))
    git(linked, 'branch', '--set-upstream-to=origin/' + branch)
    assert (linked / '.git').is_file()
    assert 'branch: linked-test' in invoke(linked, 'status')
    # A source archive nested inside a repo must not borrow its history.
    archive = repo / 'archive'
    shutil.copytree(repo / 'bin', archive / 'bin')
    shutil.copy2(repo / 'install.sh', archive / 'install.sh')
    assert 'no Git history' in invoke(archive, 'status')
    (archive / '.git').write_text('gitdir: nonexistent\n')
    (archive / '.git').unlink()
    (archive / '.git').symlink_to('nonexistent')

print('Git checkout regression tests passed')
