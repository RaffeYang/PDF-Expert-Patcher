#!/usr/bin/env python3
"""Build/installation identity. Metadata is evidence, never a runtime pass."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

from inject_lc import atomic_write

ROOT = Path(__file__).resolve().parents[1]
PATCHES = ('TabPatch', 'SidebarPatch', 'ToolbarPatch', 'KeychainFix')


def require_patch(name):
    if name not in PATCHES:
        raise ValueError('unknown patch: ' + name)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fingerprint(paths, root):
    value = hashlib.sha256()
    for relative in paths:
        value.update(relative.encode() + b'\0')
        value.update((root / relative).read_bytes())
        value.update(b'\0')
    return value.hexdigest()


def source_hash(name, root=ROOT):
    require_patch(name)
    paths = ['src/' + name + '.m']
    if name == 'KeychainFix':
        paths += ['src/vendor/fishhook.c', 'src/vendor/fishhook.h']
    return fingerprint(paths, Path(root))


def recipe_hash(root=ROOT):
    return fingerprint(['tools/build.sh', 'tools/env.sh', 'tools/provenance.py'], Path(root))


def write_json(path, record):
    path = Path(path)
    content = (json.dumps(record, indent=2, ensure_ascii=False) + '\n').encode()
    if path.exists():
        atomic_write(path, content)
    else:
        # atomic_write preserves destination mode; create an empty regular file first.
        path.touch(mode=0o644)
        atomic_write(path, content)


def write_build(name, build, root=ROOT, expected_source=None):
    require_patch(name)
    build, root = Path(build), Path(root)
    current = source_hash(name, root)
    if expected_source is not None and current != expected_source:
        raise ValueError('source changed during build; rebuild before deploying')
    record = {'schema': 1, 'patch': name,
              'project_version': (root / 'VERSION').read_text().strip(),
              'source_sha256': current, 'recipe_sha256': recipe_hash(root),
              'binary_sha256': sha(build / (name + '.dylib')),
              'built_at': datetime.now(timezone.utc).isoformat()}
    write_json(build / (name + '.json'), record)
    return record


def load_build(name, build):
    require_patch(name)
    build = Path(build)
    record = json.loads((build / (name + '.json')).read_text())
    if not isinstance(record, dict) or record.get('schema') != 1 or record.get('patch') != name:
        raise ValueError('invalid build metadata for ' + name)
    for field in ('project_version', 'source_sha256', 'recipe_sha256', 'built_at'):
        if not isinstance(record.get(field), str) or not record[field]:
            raise ValueError('missing build metadata: ' + field)
    if record.get('binary_sha256') != sha(build / (name + '.dylib')):
        raise ValueError('build/installed binary hash mismatch: ' + name)
    return record


def status(name, build, install, root=ROOT):
    require_patch(name)
    build, install, root = Path(build), Path(install), Path(root)
    library = install / (name + '.dylib')
    state = {'patch': name, 'project_version': None, 'tracked': False,
             'installed_sha256': sha(library) if library.is_file() else None,
             'metadata_valid': None, 'matches_build': None, 'matches_source': None,
             'matches_recipe': None}
    if (install / (name + '.json')).is_file():
        state['tracked'] = True
        try:
            record = load_build(name, install)
            state.update(project_version=record['project_version'], metadata_valid=True,
                         source_sha256=record['source_sha256'], built_at=record['built_at'])
            state['matches_source'] = record['source_sha256'] == source_hash(name, root)
            state['matches_recipe'] = record['recipe_sha256'] == recipe_hash(root)
        except (OSError, ValueError) as error:
            state.update(metadata_valid=False, metadata_error=str(error))
    if (build / (name + '.dylib')).is_file():
        state['build_sha256'] = sha(build / (name + '.dylib'))
        state['matches_build'] = state['installed_sha256'] == state['build_sha256']
        try:
            load_build(name, build)
            state['build_metadata_valid'] = True
        except (OSError, ValueError) as error:
            state.update(build_metadata_valid=False, build_metadata_error=str(error))
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('write', 'source'))
    parser.add_argument('patch', choices=PATCHES)
    parser.add_argument('--build')
    parser.add_argument('--expected-source')
    args = parser.parse_args()
    if args.action == 'source':
        print(source_hash(args.patch))
    else:
        if not args.build:
            parser.error('--build is required for write')
        write_build(args.patch, args.build, expected_source=args.expected_source)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
