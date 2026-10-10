import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'tools'))
import provenance


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        (self.root / 'src').mkdir()
        (self.root / 'tools').mkdir()
        (self.root / 'VERSION').write_text('1.4.0\n')
        (self.root / 'src/TabPatch.m').write_text('code')
        for name in ('build.sh', 'env.sh', 'provenance.py'):
            (self.root / 'tools' / name).write_text('recipe')
        self.build = self.root / 'build'
        self.install = self.root / 'installed'
        self.build.mkdir()
        self.install.mkdir()
        (self.build / 'TabPatch.dylib').write_bytes(b'binary')

    def tearDown(self):
        self.tmp.cleanup()

    def test_build_and_install_identity(self):
        record = provenance.write_build('TabPatch', self.build, self.root)
        self.assertEqual(record['project_version'], '1.4.0')
        self.assertEqual(provenance.load_build('TabPatch', self.build), record)
        import shutil
        for suffix in ('.dylib', '.json'):
            shutil.copy2(self.build / ('TabPatch' + suffix), self.install / ('TabPatch' + suffix))
        state = provenance.status('TabPatch', self.build, self.install, self.root)
        self.assertTrue(state['metadata_valid'])
        self.assertTrue(state['matches_build'])
        self.assertTrue(state['matches_source'])

    def test_tampered_build_rejected(self):
        provenance.write_build('TabPatch', self.build, self.root)
        (self.build / 'TabPatch.dylib').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'hash'):
            provenance.load_build('TabPatch', self.build)

    def test_source_drift_detected(self):
        import shutil
        provenance.write_build('TabPatch', self.build, self.root)
        for suffix in ('.dylib', '.json'):
            shutil.copy2(self.build / ('TabPatch' + suffix), self.install / ('TabPatch' + suffix))
        (self.root / 'src/TabPatch.m').write_text('new source')
        state = provenance.status('TabPatch', self.build, self.install, self.root)
        self.assertTrue(state['matches_build'])
        self.assertFalse(state['matches_source'])

    def test_untracked_library_does_not_claim_version(self):
        (self.install / 'TabPatch.dylib').write_bytes(b'legacy')
        state = provenance.status('TabPatch', self.build, self.install, self.root)
        self.assertIsNone(state['project_version'])
        self.assertFalse(state['tracked'])
        self.assertIsNone(state['matches_source'])

    def test_metadata_tampering_detected(self):
        import shutil
        provenance.write_build('TabPatch', self.build, self.root)
        for suffix in ('.dylib', '.json'):
            shutil.copy2(self.build / ('TabPatch' + suffix), self.install / ('TabPatch' + suffix))
        (self.install / 'TabPatch.dylib').write_bytes(b'changed')
        self.assertFalse(provenance.status('TabPatch', self.build, self.install, self.root)['metadata_valid'])

    def test_malformed_metadata_is_reported(self):
        (self.install / 'TabPatch.dylib').write_bytes(b'legacy')
        (self.install / 'TabPatch.json').write_text('[]')
        self.assertFalse(provenance.status('TabPatch', self.build, self.install, self.root)['metadata_valid'])

    def test_invalid_patch_rejected(self):
        with self.assertRaises(ValueError):
            provenance.write_build('../../bad', self.build, self.root)


if __name__ == '__main__':
    unittest.main()
