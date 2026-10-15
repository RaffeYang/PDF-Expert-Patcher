import pathlib
import plistlib
import sys
import tempfile
import unittest
from test_inject_lc import thin
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'tools'))
import compatibility
from inject_lc import patched_bytes


class CompatibilityTests(unittest.TestCase):
    def make_app(self, root, name, data):
        app = root / name
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.readdle.PDFExpert-Mac',
            'CFBundleVersion': '1177', 'CFBundleShortVersionString': '3.13.4'}))
        (app / 'Contents/MacOS/PDF Expert').write_bytes(data)
        return app

    def test_capture_never_claims_manual_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            app = self.make_app(root, 'app', thin())
            report = compatibility.capture(app, root / 'build', root / 'install')
            self.assertTrue(all(value == 'pending' for value in report['manual_validation'].values()))
            self.assertEqual(report['manual_validation'].get('context_menu'), 'pending')
            self.assertEqual(report['automated_tests'], 'not_run_by_capture')
            self.assertEqual(report['evidence'], 'read_only_observation')
            self.assertEqual(len(report['patches']), 4)

    def test_capture_binds_executable_and_actual_dependencies(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            install = root / 'lib'
            expected = str(install / 'TabPatch.dylib')
            first = self.make_app(root, 'patched.app', patched_bytes(thin(), [expected]))
            second = self.make_app(root, 'original.app', thin())
            a = compatibility.capture(first, root / 'build', install)
            b = compatibility.capture(second, root / 'build', install)
            self.assertEqual(a['app'], b['app'])
            self.assertNotEqual(a['app_identity']['executable_sha256'], b['app_identity']['executable_sha256'])
            self.assertTrue(a['patches'][0]['referenced_at_expected_path'])
            self.assertFalse(b['patches'][0]['referenced_at_expected_path'])
            self.assertEqual(a['app_identity']['slices'][0]['patch_load_paths'], [expected])

    def test_capture_rejects_invalid_macho(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            app = self.make_app(root, 'invalid.app', b'not Mach-O')
            with self.assertRaises(ValueError):
                compatibility.capture(app, root / 'build', root / 'install')

if __name__ == '__main__':
    unittest.main()
