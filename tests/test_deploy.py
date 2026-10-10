import importlib.util
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from test_inject_lc import thin

TOOLS = pathlib.Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))


def module():
    spec = importlib.util.spec_from_file_location('deploy', TOOLS / 'deploy.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class DeployTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.app = self.root / 'PDF Expert.app'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        self.info = {'CFBundleShortVersionString': '3.13.4', 'CFBundleVersion': '1234',
                     'CFBundleIdentifier': 'com.readdle.PDFExpert-Mac'}
        self.write_info()
        data = thin() + bytearray(4096)
        import struct
        data[512:528] = b'\0' * 16
        data[4096:4112] = b'x' * 16
        # Expand segment filesize/vmsize and section offset to allow realistic paths.
        struct.pack_into('<Q', data, 56, len(data))
        struct.pack_into('<Q', data, 80, len(data))
        struct.pack_into('<I', data, 152, 4096)
        (self.app / 'Contents/MacOS/PDF Expert').write_bytes(data)
        self.d = module()
        self.install = self.root / 'installed'
        self.build = self.root / 'build'
        self.build.mkdir()
        for name in self.d.PATCHES:
            binary = self.build / (name + '.dylib')
            binary.write_bytes(b'new-' + name.encode())
            from provenance import sha
            (self.build / (name + '.json')).write_text(json.dumps({
                'schema': 1, 'patch': name, 'project_version': '1.4.0',
                'source_sha256': 'a' * 64, 'recipe_sha256': 'b' * 64,
                'binary_sha256': sha(binary), 'built_at': 'test'}))
        self.calls = []
        self.fail_sign = False
        self.engine = self.d.Deployment(self.app, self.build, self.root / 'backup',
                                        self.install, runner=self.runner)

    def tearDown(self):
        self.temp.cleanup()

    def write_info(self):
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))

    def runner(self, args):
        self.calls.append(args)
        if args[0] == 'ditto':
            shutil.copytree(args[1], args[2], symlinks=True)
        if args[0] == 'codesign' and '--force' in args and self.fail_sign:
            raise RuntimeError('simulated signing failure')
        stderr = 'TeamIdentifier=3L68KQB4HG\n'
        stdout = plistlib.dumps({'com.apple.developer.team-identifier': '3L68KQB4HG',
                                'com.apple.security.cs.disable-library-validation': True}) if '--entitlements' in args and '--display' in args else b''
        return subprocess.CompletedProcess(args, 0, stdout, stderr.encode())

    def change_build(self, name):
        binary = self.build / (name + '.dylib')
        binary.write_bytes(binary.read_bytes() + b'-replacement')
        record = json.loads((self.build / (name + '.json')).read_text())
        from provenance import sha
        record['binary_sha256'] = sha(binary)
        (self.build / (name + '.json')).write_text(json.dumps(record))

    def test_single_update_does_not_change_app_or_other_modules(self):
        self.engine.install_patches()
        before = {p: p.read_bytes() for p in self.app.rglob('*') if p.is_file()}
        others = {p.name: p.read_bytes() for p in self.install.iterdir()
                  if p.name not in ('SidebarPatch.dylib', 'SidebarPatch.json', '.deploy.lock')}
        self.calls.clear()
        self.change_build('SidebarPatch')
        self.engine.update_one('SidebarPatch')
        self.assertEqual((self.install / 'SidebarPatch.dylib').read_bytes(), b'new-SidebarPatch-replacement')
        self.assertEqual(before, {p: p.read_bytes() for p in self.app.rglob('*') if p.is_file()})
        for name, content in others.items():
            self.assertEqual((self.install / name).read_bytes(), content)
        self.assertFalse(any(args[0] == 'ditto' or str(self.app) in args for args in self.calls))
        self.assertTrue(list((self.root / 'backup/updates/SidebarPatch').glob('*/SidebarPatch.dylib')))

    def test_build_race_is_rejected_before_signing(self):
        self.engine.install_patches()
        original_copy = shutil.copy2
        def racing_copy(src, dst, *args, **kwargs):
            result = original_copy(src, dst, *args, **kwargs)
            if pathlib.Path(src) == self.build / 'SidebarPatch.dylib':
                pathlib.Path(dst).write_bytes(b'raced-build')
            return result
        before = (self.install / 'SidebarPatch.dylib').read_bytes()
        with patch.object(self.d.shutil, 'copy2', side_effect=racing_copy):
            with self.assertRaisesRegex(RuntimeError, 'changed'):
                self.engine.update_one('SidebarPatch')
        self.assertEqual((self.install / 'SidebarPatch.dylib').read_bytes(), before)

    def test_single_update_requires_existing_injection(self):
        with self.assertRaisesRegex(RuntimeError, 'not injected'):
            self.engine.preflight_update('SidebarPatch')
        self.assertFalse(self.install.exists())

    def test_single_update_rejects_stale_binary_metadata(self):
        self.engine.install_patches()
        (self.build / 'SidebarPatch.dylib').write_bytes(b'untracked-new-binary')
        before = (self.install / 'SidebarPatch.dylib').read_bytes()
        with self.assertRaisesRegex(ValueError, 'hash'):
            self.engine.update_one('SidebarPatch')
        self.assertEqual((self.install / 'SidebarPatch.dylib').read_bytes(), before)

    def test_single_update_metadata_commit_failure_rolls_back_library(self):
        self.engine.install_patches()
        old_library = (self.install / 'SidebarPatch.dylib').read_bytes()
        old_record = (self.install / 'SidebarPatch.json').read_bytes()
        self.change_build('SidebarPatch')
        real_replace = self.d.os.replace
        def reject_metadata(src, dst):
            if pathlib.Path(dst) == self.install / 'SidebarPatch.json':
                raise OSError('metadata commit failed')
            return real_replace(src, dst)
        with patch.object(self.d.os, 'replace', side_effect=reject_metadata):
            with self.assertRaises(OSError):
                self.engine.update_one('SidebarPatch')
        self.assertEqual((self.install / 'SidebarPatch.dylib').read_bytes(), old_library)
        self.assertEqual((self.install / 'SidebarPatch.json').read_bytes(), old_record)

    def test_success_and_restore_full_bundle(self):
        original = (self.app / 'Contents/MacOS/PDF Expert').read_bytes()
        (self.app / 'Contents/resource').write_text('pristine')
        self.engine.install_patches()
        self.assertNotEqual((self.app / 'Contents/MacOS/PDF Expert').read_bytes(), original)
        for name in self.d.PATCHES:
            self.assertEqual((self.install / (name + '.dylib')).read_bytes(), b'new-' + name.encode())
        (self.app / 'Contents/resource').write_text('changed')
        self.engine.restore()
        self.assertEqual((self.app / 'Contents/MacOS/PDF Expert').read_bytes(), original)
        self.assertEqual((self.app / 'Contents/resource').read_text(), 'pristine')

    def test_sign_failure_leaves_app_and_libraries_unchanged(self):
        original = (self.app / 'Contents/MacOS/PDF Expert').read_bytes()
        self.install.mkdir()
        for name in self.d.PATCHES:
            (self.install / (name + '.dylib')).write_bytes(b'old')
        self.fail_sign = True
        with self.assertRaises(RuntimeError):
            self.engine.install_patches()
        self.assertEqual((self.app / 'Contents/MacOS/PDF Expert').read_bytes(), original)
        self.assertTrue(all(p.read_bytes() == b'old' for p in self.install.glob('*.dylib')))

    def test_commit_failure_rolls_back_app_and_libraries(self):
        original = (self.app / 'Contents/MacOS/PDF Expert').read_bytes()
        self.install.mkdir()
        for name in self.d.PATCHES:
            (self.install / (name + '.dylib')).write_bytes(b'old')
        real_replace = self.d.os.replace
        def fail_candidate(src, dst):
            if pathlib.Path(src).name == 'candidate.app' and pathlib.Path(dst) == self.app:
                raise OSError('simulated rename failure')
            return real_replace(src, dst)
        with patch.object(self.d.os, 'replace', side_effect=fail_candidate):
            with self.assertRaises(OSError):
                self.engine.install_patches()
        self.assertEqual((self.app / 'Contents/MacOS/PDF Expert').read_bytes(), original)
        self.assertTrue(all(p.read_bytes() == b'old' for p in self.install.glob('*.dylib')))

    def test_candidate_sign_failure_is_before_commit(self):
        original = (self.app / 'Contents/MacOS/PDF Expert').read_bytes()
        def reject_candidate(args):
            if args[0] == 'codesign' and '--force' in args and args[-1].endswith('candidate.app'):
                raise RuntimeError('candidate signing failed')
            return self.runner(args)
        self.engine.run = reject_candidate
        with self.assertRaisesRegex(RuntimeError, 'candidate signing'):
            self.engine.install_patches()
        self.assertEqual((self.app / 'Contents/MacOS/PDF Expert').read_bytes(), original)
        self.assertFalse(list(self.install.glob('*.dylib')))

    def test_final_verification_failure_rolls_back(self):
        original = (self.app / 'Contents/MacOS/PDF Expert').read_bytes()
        verified = 0
        def fail_after_commit(args):
            nonlocal verified
            if args[0] == 'codesign' and '--verify' in args and args[-1] == str(self.app):
                verified += 1
                if verified == 2:
                    raise RuntimeError('post-commit verification failed')
            return self.runner(args)
        self.engine.run = fail_after_commit
        with self.assertRaisesRegex(RuntimeError, 'post-commit'):
            self.engine.install_patches()
        self.assertEqual((self.app / 'Contents/MacOS/PDF Expert').read_bytes(), original)
        self.assertFalse(list(self.install.glob('*.dylib')))

    def test_preflight_detects_invalid_signature_before_mutations(self):
        def invalid(args):
            if args[0] == 'codesign' and '--verify' in args:
                raise RuntimeError('invalid signature')
            return self.runner(args)
        self.engine.run = invalid
        with self.assertRaisesRegex(RuntimeError, 'invalid signature'):
            self.engine.preflight()
        self.assertFalse(self.install.exists())
        self.assertFalse((self.root / 'backup').exists())

    def test_explicit_snapshot_rejects_legacy_patch(self):
        from inject_lc import patched_bytes
        exe = self.app / 'Contents/MacOS/PDF Expert'
        exe.write_bytes(patched_bytes(exe.read_bytes(), ['/old/TabPatch.dylib']))
        with self.assertRaisesRegex(RuntimeError, 'patched app'):
            self.engine.save_original()
        self.assertFalse((self.root / 'backup').exists())

    def test_explicit_original_snapshot_and_reuse(self):
        self.engine.save_original()
        self.engine.save_original()
        self.assertEqual(len(list((self.root / 'backup').glob('*/manifest.json'))), 1)

    def test_restore_rejects_different_build(self):
        self.engine.install_patches()
        self.info['CFBundleVersion'] = '9999'
        self.write_info()
        current = (self.app / 'Contents/MacOS/PDF Expert').read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'matching'):
            self.engine.restore()
        self.assertEqual((self.app / 'Contents/MacOS/PDF Expert').read_bytes(), current)

    def test_tampered_backup_rejected(self):
        self.engine.install_patches()
        snapshot = next((self.root / 'backup').glob('*/original.app/Contents/MacOS/PDF Expert'))
        snapshot.write_bytes(b'tampered')
        with self.assertRaisesRegex(RuntimeError, 'hash'):
            self.engine.restore()

    def test_legacy_patched_app_does_not_become_official_backup(self):
        from inject_lc import patched_bytes
        exe = self.app / 'Contents/MacOS/PDF Expert'
        exe.write_bytes(patched_bytes(exe.read_bytes(), ['/tmp/TabPatch.dylib']))
        self.engine.install_patches()
        self.assertFalse(list((self.root / 'backup').glob('*/manifest.json')))
        with self.assertRaisesRegex(RuntimeError, 'matching'):
            self.engine.restore()


if __name__ == '__main__':
    unittest.main()
