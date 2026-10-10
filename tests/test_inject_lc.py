import pathlib
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'tools/inject_lc.py'


def thin():
    data = bytearray(1024)
    struct.pack_into('<8I', data, 0, 0xFEEDFACF, 0x01000007, 3, 2, 1, 152, 0, 0)
    struct.pack_into('<II16sQQQQIIII', data, 32, 0x19, 152, b'__TEXT',
                     0, 1024, 0, 1024, 7, 5, 1, 0)
    struct.pack_into('<16s16sQQIIIIIIII', data, 104, b'__text', b'__TEXT',
                     512, 16, 512, 0, 0, 0, 0, 0, 0, 0)
    data[512:528] = b'x' * 16
    return data


def fat(a, b):
    data = bytearray(4096)
    struct.pack_into('>II', data, 0, 0xCAFEBABE, 2)
    struct.pack_into('>5I', data, 8, 0x01000007, 3, 1024, len(a), 10)
    struct.pack_into('>5I', data, 28, 0x0100000C, 0, 2048, len(b), 10)
    data[1024:1024 + len(a)] = a
    data[2048:2048 + len(b)] = b
    return data


class InjectorTests(unittest.TestCase):
    def invoke(self, data, success, repeat=False):
        with tempfile.TemporaryDirectory() as tmp:
            exe = pathlib.Path(tmp) / 'test'
            exe.write_bytes(data)
            exe.chmod(0o755)
            cmd = [sys.executable, str(SCRIPT), str(exe), '/tmp/Test.dylib']
            result = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, success, result.stderr + result.stdout)
            after = exe.read_bytes()
            self.assertEqual(exe.stat().st_mode & 0o777, 0o755)
            if not success:
                self.assertEqual(after, data, 'failure must not modify input')
            if repeat:
                result = subprocess.run(cmd, capture_output=True)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(exe.read_bytes(), after)
            return after

    def test_thin_and_fat_idempotent(self):
        for data in (thin(), fat(thin(), thin())):
            self.invoke(data, True, True)

    def test_nonzero_padding_rejected(self):
        data = thin()
        data[184] = 42
        self.invoke(data, False)

    def test_load_command_outside_declared_size(self):
        data = thin()
        struct.pack_into('<I', data, 20, 8)
        self.invoke(data, False)

    def test_section_outside_slice(self):
        data = thin()
        struct.pack_into('<I', data, 152, 4096)
        self.invoke(data, False)

    def test_bad_fat_slice_does_not_write_first(self):
        data = thin()
        struct.pack_into('<I', data, 0, 0)
        self.invoke(fat(thin(), data), False)

    def test_overlapping_slices(self):
        data = fat(thin(), thin())
        struct.pack_into('>I', data, 36, 1024)
        self.invoke(data, False)

    def test_migrate_old_dylib_paths(self):
        sys.path.insert(0, str(SCRIPT.parent))
        from inject_lc import patched_bytes, migrated_bytes, load_paths
        old = patched_bytes(thin(), ['/old/TabPatch.dylib', '/other/keep.dylib'])
        new = migrated_bytes(old, ['/new/TabPatch.dylib'])
        self.assertEqual(load_paths(new), [['/new/TabPatch.dylib', '/other/keep.dylib']])

    def test_migration_rejects_duplicate_patch_ordinals(self):
        sys.path.insert(0, str(SCRIPT.parent))
        from inject_lc import patched_bytes, migrated_bytes, MachOError
        original = patched_bytes(thin(), ['/a/TabPatch.dylib', '/b/TabPatch.dylib'])
        with self.assertRaisesRegex(MachOError, 'duplicate patch'):
            migrated_bytes(original, ['/new/TabPatch.dylib'])

    def test_migration_preserves_code_and_is_idempotent(self):
        sys.path.insert(0, str(SCRIPT.parent))
        from inject_lc import patched_bytes, migrated_bytes, load_paths
        old = patched_bytes(thin(), ['/old/TabPatch.dylib', '/other/keep.dylib'])
        paths = ['/much/longer/path/TabPatch.dylib', '/new/SidebarPatch.dylib']
        result = migrated_bytes(old, paths)
        self.assertEqual(result[512:], old[512:])
        self.assertEqual(load_paths(result)[0], [paths[0], '/other/keep.dylib', paths[1]])
        self.assertEqual(migrated_bytes(result, paths), result)

    def test_fat64_container(self):
        data = bytearray(2048)
        struct.pack_into('>II', data, 0, 0xCAFEBABF, 1)
        struct.pack_into('>IIQQII', data, 8, 0x01000007, 3, 1024, 1024, 10, 0)
        data[1024:] = thin()
        self.invoke(data, True, True)

    def test_insufficient_slack(self):
        data = thin()
        struct.pack_into('<I', data, 152, 192)
        self.invoke(data, False)

    def test_zerofill_section_is_not_header_slack(self):
        data = thin()
        struct.pack_into('<I', data, 168, 1)
        self.invoke(data, False)

    def test_invalid_dylib_name_offset(self):
        import sys
        sys.path.insert(0, str(SCRIPT.parent))
        from inject_lc import patched_bytes
        data = bytearray(patched_bytes(thin(), ['/other/library.dylib']))
        struct.pack_into('<I', data, 192, 4096)
        self.invoke(data, False)

    def test_truncated_input(self):
        for data in (b'', b'\xcf\xfa\xed\xfe', thin()[:100]):
            self.invoke(data, False)


if __name__ == '__main__':
    unittest.main()
