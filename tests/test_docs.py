import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class DocumentationTests(unittest.TestCase):
    def test_current_document_links_resolve(self):
        files = [ROOT / 'README.md', ROOT / 'AGENTS.md'] + list((ROOT / 'docs').glob('*.md'))
        for document in files:
            for target in re.findall(r'\[[^\]]*\]\(([^)\n]+)\)', document.read_text()):
                if '://' in target or target.startswith('#'):
                    continue
                target = target.split('#')[0]
                with self.subTest(document=document.name, target=target):
                    self.assertTrue((document.parent / target).exists())

    def test_manual_baseline_is_explicit_and_hash_bound(self):
        data = json.loads((ROOT / 'docs/compatibility.json').read_text())
        self.assertEqual(data['schema'], 1)
        for record in data['records']:
            self.assertIn(record['evidence'], ('user_confirmation', 'maintainer_manual_validation'))
            self.assertTrue(record['statement'])
            for patch in record['patches']:
                self.assertRegex(patch['binary_sha256'], '^[a-f0-9]{64}$')
            self.assertIn('login_restart', record['manual_validation'])

if __name__ == '__main__':
    unittest.main()
