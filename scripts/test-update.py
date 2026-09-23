#!/usr/bin/env python3
"""Real Git, harmless installer: no network or host installation."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tk-update-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.env = {**os.environ, 'HOME': str(self.base / 'home'),
                    'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_NOSYSTEM': '1',
                    'INSTALL_LOG': str(self.base / 'installed')}
        for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR'):
            self.env.pop(key, None)
        Path(self.env['HOME']).mkdir()
        self.seed = self.base / 'seed'
        self.seed.mkdir()
        self.git(self.seed, 'init', '-qb', 'main')
        self.git(self.seed, 'config', 'user.name', 'Fixture')
        self.git(self.seed, 'config', 'user.email', 'fixture@example.invalid')
        for file in ('bin/terminal-kit', 'scripts/update.py'):
            path = self.seed / file
            path.parent.mkdir(exist_ok=True)
            shutil.copy2(ROOT / file, path)
        (self.seed / 'install.sh').write_text('printf "installed\\n" >> "$INSTALL_LOG"\n')
        (self.seed / 'value').write_text('old')
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-qm', 'base')
        self.old = self.git(self.seed, 'rev-parse', 'HEAD')
        self.remote = self.base / 'remote.git'
        self.run_cmd('git', 'clone', '-q', '--bare', str(self.seed), str(self.remote))
        self.git(self.seed, 'remote', 'add', 'origin', str(self.remote))
        self.repo = self.base / 'repo'
        self.run_cmd('git', 'clone', '-q', str(self.remote), str(self.repo))
        self.state = self.repo / '.git/terminal-kit-update'

    def run_cmd(self, *args, ok=True):
        result = subprocess.run(args, env=self.env, text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def git(self, repo, *args):
        return self.run_cmd('git', '-C', str(repo), *args).stdout.strip()

    def command(self, *args, ok=True):
        return self.run_cmd('bash', str(self.repo / 'bin/terminal-kit'), *args, ok=ok)

    def candidate(self, installer=None):
        (self.seed / 'value').write_text('new')
        if installer is not None:
            (self.seed / 'install.sh').write_text(installer)
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-qm', 'candidate')
        self.git(self.seed, 'push', '-q', 'origin', 'main')
        return self.git(self.seed, 'rev-parse', 'HEAD')

    def assert_not_installed(self):
        self.assertFalse(Path(self.env['INSTALL_LOG']).exists())
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), self.old)

    def test_preview_apply_and_source_rollback(self):
        target = self.candidate()
        output = self.command('update').stdout
        self.assertIn(target, output)
        self.assert_not_installed()
        (self.repo / 'harmless.pyc').write_bytes(b'cache')
        output = self.command('update', '--apply', target).stdout
        self.assertIn('Independent source rollback', output)
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), target)
        self.assertTrue(Path(self.env['INSTALL_LOG']).exists())
        self.command('rollback')
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), self.old)
        self.assertTrue((self.repo / 'harmless.pyc').exists())
        self.assertTrue(Path(self.env['INSTALL_LOG']).exists(), 'host effects must not be claimed undone')

    def test_apply_requires_exact_untampered_plan(self):
        target = self.candidate()
        self.assertNotEqual(self.command('update', '--apply', target, ok=False).returncode, 0)
        self.command('update')
        self.assertNotEqual(self.command('update', '--apply', target[:10], ok=False).returncode, 0)
        path = self.state / 'plan.json'
        record = json.loads(path.read_text())
        record['plan']['remote_url'] = 'changed'
        path.write_text(json.dumps(record))
        self.assertNotEqual(self.command('update', '--apply', target, ok=False).returncode, 0)
        self.assert_not_installed()

    def test_changed_remote_or_tracked_files_reject(self):
        target = self.candidate()
        self.command('update')
        self.git(self.repo, 'remote', 'set-url', 'origin', str(self.base / 'elsewhere'))
        self.assertNotEqual(self.command('update', '--apply', target, ok=False).returncode, 0)
        self.git(self.repo, 'remote', 'set-url', 'origin', str(self.remote))
        (self.repo / 'value').write_text('user changes')
        self.assertNotEqual(self.command('update', '--apply', target, ok=False).returncode, 0)
        self.assertEqual((self.repo / 'value').read_text(), 'user changes')
        self.assert_not_installed()

    def test_failed_installer_restores_source_without_candidate_updater(self):
        (self.seed / 'scripts/update.py').unlink()
        target = self.candidate('printf "installed\\n" >> "$INSTALL_LOG"\nexit 17\n')
        self.command('update')
        result = self.command('update', '--apply', target, ok=False)
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), self.old)
        self.assertTrue((self.repo / 'scripts/update.py').exists())
        receipt = Path(json.loads((self.state / 'latest.json').read_text())['receipt'])
        self.assertTrue(receipt.with_name('recover.py').exists())
        self.assertEqual(json.loads(receipt.read_text())['state'], 'source-restored')

    def test_rollback_preserves_user_edits(self):
        target = self.candidate()
        self.command('update')
        self.command('update', '--apply', target)
        (self.repo / 'value').write_text('user changes')
        self.assertNotEqual(self.command('rollback', ok=False).returncode, 0)
        self.assertEqual((self.repo / 'value').read_text(), 'user changes')
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), target)

    def test_untracked_collision_is_preserved(self):
        (self.seed / 'added').write_text('incoming')
        target = self.candidate()
        self.command('update')
        (self.repo / 'added').write_text('user file')
        self.assertNotEqual(self.command('update', '--apply', target, ok=False).returncode, 0)
        self.assertEqual((self.repo / 'added').read_text(), 'user file')
        self.assert_not_installed()

    def test_ignored_untracked_collision_is_preserved(self):
        (self.seed / 'added').write_text('incoming')
        target = self.candidate()
        self.command('update')
        (self.repo / '.git/info/exclude').write_text('added\n')
        (self.repo / 'added').write_text('user ignored data')
        self.assertNotEqual(self.command('update', '--apply', target, ok=False).returncode, 0)
        self.assertEqual((self.repo / 'added').read_text(), 'user ignored data')
        self.assert_not_installed()

    def test_rollback_preserves_ignored_reintroduced_path(self):
        (self.seed / 'value').unlink()
        # Commit a candidate deletion without candidate() recreating value.
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-qm', 'remove value')
        self.git(self.seed, 'push', '-q', 'origin', 'main')
        target = self.git(self.seed, 'rev-parse', 'HEAD')
        self.command('update')
        self.command('update', '--apply', target)
        (self.repo / '.git/info/exclude').write_text('value\n')
        (self.repo / 'value').write_text('user ignored data')
        self.assertNotEqual(self.command('rollback', ok=False).returncode, 0)
        self.assertEqual((self.repo / 'value').read_text(), 'user ignored data')
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), target)

    def test_rollback_preserves_ignored_symlink_parent(self):
        (self.seed / 'folder').mkdir()
        (self.seed / 'folder/note').write_text('original')
        self.git(self.seed, 'add', '.')
        self.git(self.seed, 'commit', '-qm', 'old directory')
        self.git(self.seed, 'push', '-q', 'origin', 'main')
        self.git(self.repo, 'pull', '--ff-only')
        self.old = self.git(self.repo, 'rev-parse', 'HEAD')
        self.git(self.seed, 'rm', '-r', 'folder')
        self.git(self.seed, 'commit', '-qm', 'remove directory')
        self.git(self.seed, 'push', '-q', 'origin', 'main')
        target = self.git(self.seed, 'rev-parse', 'HEAD')
        self.command('update')
        self.command('update', '--apply', target)
        outside = self.base / 'outside'
        outside.mkdir()
        (outside / 'note').write_text('outside user data')
        (self.repo / '.git/info/exclude').write_text('folder\n')
        (self.repo / 'folder').symlink_to(outside, target_is_directory=True)
        self.assertNotEqual(self.command('rollback', ok=False).returncode, 0)
        self.assertTrue((self.repo / 'folder').is_symlink())
        self.assertEqual((outside / 'note').read_text(), 'outside user data')
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), target)

    def test_rollback_preserves_filesystem_case_and_unicode_aliases(self):
        pairs = [('value', 'VALUE'), ('CAFÉ', 'café'), ('Σ', 'σ'), ('σ', 'ς'), ('K', 'K'), ('café', 'cafe\u0301')]
        for number, (original, local) in enumerate(pairs):
            with self.subTest(original=original, local=local):
                repo = self.base / f'alias-{number}'
                repo.mkdir()
                self.git(repo, 'init', '-qb', 'main')
                self.git(repo, 'config', 'user.name', 'Fixture')
                self.git(repo, 'config', 'user.email', 'fixture@example.invalid')
                (repo / original).write_text('original source')
                self.git(repo, 'add', '.')
                self.git(repo, 'commit', '-qm', 'original')
                previous = self.git(repo, 'rev-parse', 'HEAD')
                self.git(repo, 'rm', '--', original)
                self.git(repo, 'commit', '-qm', 'candidate removes original')
                candidate = self.git(repo, 'rev-parse', 'HEAD')
                self.git(repo, 'update-ref', 'refs/terminal-kit/test/previous', previous)
                (repo / '.git/info/exclude').write_text('*\n')
                (repo / local).write_text('USER DATA')
                aliases = os.path.lexists(repo / original)
                receipt = self.base / f'alias-{number}.json'
                receipt.write_text(json.dumps({'root': str(repo), 'branch': 'refs/heads/main',
                    'base': previous, 'target': candidate, 'previous_ref': 'refs/terminal-kit/test/previous',
                    'state': 'applied'}))
                result = self.run_cmd('python3', str(ROOT / 'scripts/update.py'), '--root', str(repo),
                                      'rollback', '--receipt', str(receipt), ok=False)
                if aliases:
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertEqual(self.git(repo, 'rev-parse', 'HEAD'), candidate)
                else:
                    # On a case-sensitive filesystem these are independent names.
                    self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((repo / local).read_text(), 'USER DATA')

    def test_linked_worktree_and_independent_recovery(self):
        linked = self.base / 'linked'
        self.git(self.repo, 'worktree', 'add', '-qb', 'linked', str(linked))
        self.git(linked, 'branch', '--set-upstream-to=origin/main')
        self.repo = linked
        target = self.candidate()
        self.command('update')
        self.command('update', '--apply', target)
        state = Path(self.git(linked, 'rev-parse', '--absolute-git-dir')) / 'terminal-kit-update'
        receipt = Path(json.loads((state / 'latest.json').read_text())['receipt'])
        self.run_cmd('python3', str(receipt.with_name('recover.py')), '--root', str(linked), 'rollback', '--receipt', str(receipt))
        self.assertEqual(self.git(linked, 'rev-parse', 'HEAD'), self.old)

    def test_stale_branch_and_head_reject(self):
        target = self.candidate()
        self.command('update')
        self.git(self.repo, 'checkout', '-qb', 'other')
        self.git(self.repo, 'branch', '--set-upstream-to=origin/main')
        self.assertNotEqual(self.command('update', '--apply', target, ok=False).returncode, 0)
        self.git(self.repo, 'checkout', '-q', 'main')
        self.git(self.repo, 'merge', '--ff-only', target)
        self.assertNotEqual(self.command('update', '--apply', target, ok=False).returncode, 0)
        self.assertFalse(Path(self.env['INSTALL_LOG']).exists())

    def test_installer_edits_block_automatic_rollback(self):
        target = self.candidate('printf "changed by installer" > "$(dirname "$0")/value"\nexit 19\n')
        self.command('update')
        result = self.command('update', '--apply', target, ok=False)
        self.assertEqual(result.returncode, 19)
        self.assertIn('Automatic source rollback stopped', result.stderr)
        self.assertEqual((self.repo / 'value').read_text(), 'changed by installer')
        self.assertEqual(self.git(self.repo, 'rev-parse', 'HEAD'), target)

    def test_divergence_and_invalid_index_do_not_install(self):
        self.candidate()
        self.git(self.repo, 'config', 'user.name', 'Fixture')
        self.git(self.repo, 'config', 'user.email', 'fixture@example.invalid')
        (self.repo / 'local').write_text('local')
        self.git(self.repo, 'add', 'local')
        self.git(self.repo, 'commit', '-qm', 'local')
        self.assertNotEqual(self.command('update', ok=False).returncode, 0)
        (self.repo / '.git/index').write_bytes(b'bad index')
        self.assertNotEqual(self.command('update', ok=False).returncode, 0)
        self.assertFalse(Path(self.env['INSTALL_LOG']).exists())


if __name__ == '__main__':
    unittest.main()
