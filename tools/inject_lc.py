#!/usr/bin/env python3
"""Validated, atomic LC_LOAD_DYLIB insertion for thin/fat 64-bit Mach-O files."""
import os
import pathlib
import stat
import struct
import sys
import tempfile

LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_SEGMENT_64 = 0x19
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
DYLIB_COMMANDS = {0xC, 0x18, 0x80000018, 0x8000001F, 0x80000023}
ZEROFILL = {1, 0xC, 0x12}


class MachOError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise MachOError(message)


def slices(data):
    require(len(data) >= 4, 'truncated magic')
    magic = struct.unpack_from('>I', data)[0]
    if struct.unpack_from('<I', data)[0] == MH_MAGIC_64:
        return [(0, len(data))]
    require(magic in (FAT_MAGIC, FAT_MAGIC_64), 'unsupported container magic')
    require(len(data) >= 8, 'truncated fat header')
    count = struct.unpack_from('>I', data, 4)[0]
    stride = 20 if magic == FAT_MAGIC else 32
    table_end = 8 + count * stride
    require(count > 0 and table_end <= len(data), 'invalid fat architecture table')
    result = []
    for i in range(count):
        entry = 8 + i * stride
        if stride == 20:
            _, _, offset, size, align = struct.unpack_from('>5I', data, entry)
        else:
            _, _, offset, size, align, _ = struct.unpack_from('>IIQQII', data, entry)
        require(align <= 63 and offset % (1 << align) == 0, 'invalid fat alignment')
        require(offset >= table_end and size >= 32 and offset + size <= len(data),
                'fat slice outside file')
        require(all(offset + size <= start or offset >= start + length
                    for start, length in result), 'overlapping fat slices')
        result.append((offset, size))
    return result


def inspect_slice(data, base, size):
    end = base + size
    require(size >= 32, 'truncated Mach-O header')
    header = struct.unpack_from('<8I', data, base)
    require(header[0] == MH_MAGIC_64, 'slice is not little-endian 64-bit Mach-O')
    count, length = header[4:6]
    lc_end = base + 32 + length
    require(lc_end <= end and count <= length // 8, 'invalid load command bounds')
    commands, paths, sections = [], [], []
    pos = base + 32
    for _ in range(count):
        require(pos + 8 <= lc_end, 'truncated load command')
        cmd, cmdsize = struct.unpack_from('<II', data, pos)
        require(cmdsize >= 8 and cmdsize % 8 == 0 and pos + cmdsize <= lc_end,
                'invalid load command size')
        commands.append((pos, cmd, cmdsize))
        if cmd in DYLIB_COMMANDS:
            require(cmdsize >= 24, 'truncated dylib command')
            name = struct.unpack_from('<I', data, pos + 8)[0]
            require(24 <= name < cmdsize, 'invalid dylib name offset')
            raw = bytes(data[pos + name:pos + cmdsize])
            require(b'\0' in raw, 'unterminated dylib name')
            paths.append(raw.split(b'\0', 1)[0].decode('utf-8', 'strict'))
        if cmd == LC_SEGMENT_64:
            require(cmdsize >= 72, 'truncated segment')
            fileoff, filesize = struct.unpack_from('<QQ', data, pos + 40)
            require(fileoff + filesize <= size, 'segment outside slice')
            nsects = struct.unpack_from('<I', data, pos + 64)[0]
            require(72 + 80 * nsects == cmdsize, 'invalid section table')
            for i in range(nsects):
                section = pos + 72 + 80 * i
                section_size = struct.unpack_from('<Q', data, section + 40)[0]
                offset = struct.unpack_from('<I', data, section + 48)[0]
                flags = struct.unpack_from('<I', data, section + 64)[0]
                if section_size and (flags & 0xFF) not in ZEROFILL:
                    require(offset >= 32 + length and offset + section_size <= size,
                            'section outside slice or overlaps load commands')
                    require(fileoff <= offset and offset + section_size <= fileoff + filesize,
                            'section outside file-backed segment')
                    sections.append(base + offset)
        pos += cmdsize
    require(pos == lc_end, 'load commands do not match sizeofcmds')
    return count, length, lc_end, paths, sections


def load_paths(data):
    return [inspect_slice(data, base, size)[3] for base, size in slices(data)]


def patch_slice(data, base, size, path):
    count, length, lc_end, paths, sections = inspect_slice(data, base, size)
    if path in paths:
        return 'already'
    require(sections, 'no file-backed sections found')
    raw = path.encode('utf-8') + b'\0'
    cmdsize = (24 + len(raw) + 7) & ~7
    require(lc_end + cmdsize <= min(sections), 'not enough header slack')
    require(not any(data[lc_end:lc_end + cmdsize]), 'header padding is not zero-filled')
    command = struct.pack('<6I', LC_LOAD_DYLIB, cmdsize, 24, 2, 0x10000, 0x10000)
    command += raw + b'\0' * (cmdsize - 24 - len(raw))
    data[lc_end:lc_end + cmdsize] = command
    struct.pack_into('<II', data, base + 16, count + 1, length + cmdsize)
    return 'patched'


def patched_bytes(source, paths):
    require(all(p and '\0' not in p for p in paths), 'empty path or embedded NUL')
    data = bytearray(source)
    architecture_slices = slices(data)
    # Validate every slice before editing any of them.
    for base, size in architecture_slices:
        inspect_slice(data, base, size)
    for path in paths:
        for base, size in architecture_slices:
            patch_slice(data, base, size, path)
    return bytes(data)


def migrated_bytes(source, paths):
    """Rewrite patch commands at their existing ordinals; append only new deps.

    Never remove/reorder dependency commands: dyld bind/chained imports and
    nlist entries refer to their 1-based ordinals. Duplicates are rejected rather
    than silently renumbered. The legacy unsafe `first` insertion is unsupported.
    """
    require(all(p and '\0' not in p for p in paths), 'empty path or embedded NUL')
    replacements = {pathlib.PurePosixPath(p).name: p for p in paths}
    require(len(replacements) == len(paths), 'duplicate requested patch names')
    data = bytearray(source)
    for base, size in slices(data):
        count, length, end, _, sections = inspect_slice(data, base, size)
        pos, commands, seen = base + 32, [], set()
        for _ in range(count):
            cmd, cmdsize = struct.unpack_from('<II', data, pos)
            command = bytes(data[pos:pos + cmdsize])
            if cmd in DYLIB_COMMANDS:
                offset = struct.unpack_from('<I', data, pos + 8)[0]
                old_path = command[offset:].split(b'\0', 1)[0].decode('utf-8')
                name = pathlib.PurePosixPath(old_path).name
                if name in replacements:
                    require(name not in seen, 'duplicate patch dependencies; restore official app before migration')
                    seen.add(name)
                    raw = replacements[name].encode('utf-8') + b'\0'
                    new_size = (24 + len(raw) + 7) & ~7
                    # Keep command type, timestamp and version fields unchanged.
                    stamp, current, compat = struct.unpack_from('<III', command, 12)
                    command = struct.pack('<6I', cmd, new_size, 24, stamp, current, compat)
                    command += raw + b'\0' * (new_size - 24 - len(raw))
            commands.append(command)
            pos += cmdsize
        rebuilt = b''.join(commands)
        new_end = base + 32 + len(rebuilt)
        require(sections and new_end <= min(sections), 'not enough header slack for path migration')
        if new_end > end:
            require(not any(data[end:new_end]), 'header padding is not zero-filled')
        write_end = max(end, new_end)
        data[base + 32:write_end] = rebuilt + b'\0' * (write_end - new_end)
        struct.pack_into('<II', data, base + 16, count, len(rebuilt))
    # Existing dependencies match and are skipped; missing patches append last.
    return patched_bytes(data, paths)


def atomic_write(path, data):
    mode = stat.S_IMODE(path.stat().st_mode)
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def main():
    if len(sys.argv) != 3:
        raise MachOError('usage: inject_lc.py <executable> <dylib-path>')
    path = pathlib.Path(sys.argv[1])
    require(not path.is_symlink(), 'refusing symlink executable')
    source = path.read_bytes()
    result = patched_bytes(source, [sys.argv[2]])
    if result != source:
        atomic_write(path, result)
    print('inject_lc: ' + ('patched' if result != source else 'already injected'))


if __name__ == '__main__':
    try:
        main()
    except (MachOError, OSError, UnicodeError, struct.error) as error:
        print('inject_lc: ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
