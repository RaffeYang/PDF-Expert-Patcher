import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class CLITests(unittest.TestCase):
    def test_help_lists_maintenance_commands(self):
        result = subprocess.run([str(ROOT / 'patch.sh'), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        for command in ('--update', '--status-json', '--record-compatibility'):
            self.assertIn(command, result.stdout)

    def test_invalid_requests_rejected_before_build_or_app_access(self):
        for arguments in (['--build', 'bad'], ['--build', '../KeychainFix'], ['--update'],
                          ['--update', 'bad'], ['--check', 'SidebarPatch'], ['--help', 'extra'],
                          ['--test', 'extra'], ['--unknown']):
            with self.subTest(arguments=arguments):
                result = subprocess.run([str(ROOT / 'patch.sh')] + arguments, capture_output=True)
                self.assertEqual(result.returncode, 2)

if __name__ == '__main__':
    unittest.main()
