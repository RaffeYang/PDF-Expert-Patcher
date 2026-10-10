#!/usr/bin/env python3
"""Prepare/sign a copy, then commit with rollback. No credential data is read."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import struct
import sys
import tempfile
import time

from inject_lc import atomic_write, load_paths, migrated_bytes, slices
from provenance import PATCHES, load_build, require_patch, sha, status, write_json

PATCH_NAMES = {name + '.dylib' for name in PATCHES}
TEAM = '3L68KQB4HG'
BUNDLE_ID = 'com.readdle.PDFExpert-Mac'


def run(args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True)


def executable(app):
    return app / 'Contents/MacOS/PDF Expert'


def metadata(app):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise RuntimeError('target is not the supported PDF Expert DMG bundle')
    return {key: str(info[key]) for key in
            ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion')}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity_report(app, build, install):
    app, install = Path(app).resolve(), Path(install).absolute()
    data = executable(app).read_bytes()
    paths = load_paths(data)
    identities = []
    for index, ((base, _), dependencies) in enumerate(zip(slices(data), paths)):
        cpu = struct.unpack_from('<I', data, base + 4)[0]
        identities.append({'index': index,
                           'architecture': {0x1000007: 'x86_64', 0x100000c: 'arm64'}.get(cpu, hex(cpu)),
                           'patch_load_paths': [p for p in dependencies if Path(p).name in PATCH_NAMES]})
    patches = []
    for name in PATCHES:
        item = status(name, build, install)
        expected = str(install / (name + '.dylib'))
        item['referenced_at_expected_path'] = all(group.count(expected) == 1 for group in paths)
        patches.append(item)
    return {'schema': 1, 'scope': 'static identity only; use --check for signatures',
            'app': metadata(app),
            'app_identity': {'path': str(app), 'executable_sha256': hashlib.sha256(data).hexdigest(),
                             'slices': identities}, 'patches': patches}


def is_patched(app):
    return any(Path(p).name in PATCH_NAMES for paths in load_paths(executable(app).read_bytes()) for p in paths)


class Deployment:
    def __init__(self, app, build, backup, install, runner=run):
        self.app = Path(app).absolute()
        self.build = Path(build).absolute()
        self.backup = Path(backup).absolute()
        self.install = Path(install).absolute()
        self.run = runner

    def copy_app(self, src, dst):
        self.run(['ditto', str(src), str(dst)])

    def verify(self, app, official=False):
        self.run(['codesign', '--verify', '--deep', '--strict', str(app)])
        if official:
            details = self.run(['codesign', '--display', '--verbose=4', str(app)])
            if ('TeamIdentifier=' + TEAM) not in details.stderr.decode():
                raise RuntimeError('full original backup requires a valid Readdle signature')

    @contextlib.contextmanager
    def locked(self):
        self.install.mkdir(parents=True, exist_ok=True)
        with (self.install / '.deploy.lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('another deployment is running')
            yield

    def snapshot_original(self):
        if is_patched(self.app):
            print('NOTICE: legacy/patched app; no new official snapshot. Existing full backups are retained.')
            return
        self.verify(self.app, official=True)
        info = metadata(self.app)
        sha = digest(executable(self.app))
        key = '-'.join(info[k] for k in ('CFBundleShortVersionString', 'CFBundleVersion'))
        key = re.sub(r'[^a-zA-Z0-9._-]', '_', key) + '-' + sha[:16]
        self.backup.mkdir(parents=True, exist_ok=True)
        destination = self.backup / key
        if destination.exists():
            self.validate_snapshot(destination, info)
            return
        with tempfile.TemporaryDirectory(prefix='.snapshot-', dir=self.backup) as tmp:
            tmp = Path(tmp)
            self.copy_app(self.app, tmp / 'original.app')
            self.verify(tmp / 'original.app', official=True)
            if digest(executable(tmp / 'original.app')) != sha:
                raise RuntimeError('application changed while creating backup')
            (tmp / 'manifest.json').write_text(json.dumps({
                'schema': 1, 'metadata': info, 'executable_sha256': sha,
                'created': time.time()}, indent=2) + '\n')
            # Move the contents into a unique final directory after validation.
            os.rename(tmp, destination)
        print('Full official backup: ' + str(destination))

    def validate_snapshot(self, directory, info):
        manifest = json.loads((directory / 'manifest.json').read_text())
        original = directory / 'original.app'
        if manifest.get('schema') != 1 or manifest.get('metadata') != info or metadata(original) != info:
            raise RuntimeError('backup has no matching version/build metadata')
        if digest(executable(original)) != manifest.get('executable_sha256'):
            raise RuntimeError('backup executable hash mismatch')
        if is_patched(original):
            raise RuntimeError('backup is patched, refusing official restore')
        self.verify(original, official=True)
        return original

    def find_original(self):
        info = metadata(self.app)
        candidates = []
        for manifest in self.backup.glob('*/manifest.json'):
            data = json.loads(manifest.read_text())
            if data.get('metadata') == info:
                candidates.append((data.get('created', 0), manifest.parent))
        if not candidates:
            raise RuntimeError('no matching complete official backup; legacy executable backups cannot restore bundle signatures')
        return self.validate_snapshot(max(candidates, key=lambda entry: entry[0])[1], info)

    def sign_candidate(self, candidate, work):
        # Entitlements come from the validated current app, before modifying it.
        result = self.run(['codesign', '--display', '--entitlements', ':-', str(self.app)])
        ent = plistlib.loads(result.stdout) if result.stdout.strip() else {}
        ent = {key: value for key, value in ent.items()
               if key not in ('com.apple.developer.team-identifier',
                              'com.apple.developer.associated-domains', 'keychain-access-groups')
               and not key.startswith(('com.apple.developer.icloud', 'com.apple.developer.ubiquity'))}
        ent_file = work / 'entitlements.plist'
        ent_file.write_bytes(plistlib.dumps(ent))
        self.run(['codesign', '--force', '--sign', '-', '--entitlements', str(ent_file), str(candidate)])
        self.verify(candidate)

    def commit(self, candidate, work, libraries=None, expected_app_hash=None):
        """Rollback on process errors; preserve recovery files if rollback itself fails."""
        retired = work / 'previous.app'
        old_libraries = work / 'previous-libraries'
        old_libraries.mkdir()
        replaced = []
        moved_app = False
        installed_app = False
        try:
            if expected_app_hash and digest(executable(self.app)) != expected_app_hash:
                raise RuntimeError('app changed before commit; wait for the external updater')
            for name, source in (libraries or {}).items():
                destination = self.install / name
                if destination.is_symlink():
                    raise RuntimeError('refusing symlink library: ' + str(destination))
                previous = old_libraries / name
                if destination.exists():
                    shutil.copy2(destination, previous)
                # Register before replacement, so a failure during the copy also rolls back.
                replaced.append((destination, previous))
                tmp = work / ('commit-' + name)
                shutil.copy2(source, tmp)
                # work is on the app volume; the install directory might be on another volume.
                fd, near = tempfile.mkstemp(prefix='.dylib-', dir=self.install)
                os.close(fd)
                try:
                    shutil.copy2(tmp, near)
                    os.replace(near, destination)
                finally:
                    if os.path.exists(near):
                        os.unlink(near)
            if candidate is not None:
                os.replace(self.app, retired)
                moved_app = True
                os.replace(candidate, self.app)
                installed_app = True
                self.verify(self.app)
            for name, source in (libraries or {}).items():
                destination = self.install / name
                if sha(destination) != sha(source):
                    raise RuntimeError('installed artifact hash mismatch: ' + name)
                if name.endswith('.dylib'):
                    self.run(['codesign', '--verify', '--strict', str(destination)])
            if candidate is None and expected_app_hash and digest(executable(self.app)) != expected_app_hash:
                raise RuntimeError('app changed during module update; rolling back module')
        except BaseException:
            try:
                if installed_app:
                    os.replace(self.app, candidate)
                if moved_app:
                    os.replace(retired, self.app)
                for destination, previous in reversed(replaced):
                    if previous.exists():
                        shutil.copy2(previous, destination)
                    elif destination.exists():
                        destination.unlink()
            except BaseException as rollback_error:
                # Caller must retain this directory for manual recovery.
                (work / 'RECOVERY_REQUIRED').write_text(str(rollback_error))
                raise RuntimeError('rollback failed; recovery files retained at ' + str(work)) from rollback_error
            raise

    @contextlib.contextmanager
    def workspace(self, libraries_only=False):
        parent = self.install if libraries_only else self.app.parent
        directory = Path(tempfile.mkdtemp(prefix='.pepatch-', dir=parent))
        try:
            yield directory
        finally:
            if not (directory / 'RECOVERY_REQUIRED').exists():
                shutil.rmtree(directory)

    def preflight(self):
        """Read-only validation before the shell asks the user app to quit."""
        metadata(self.app)
        if self.app.is_symlink() or executable(self.app).is_symlink():
            raise RuntimeError('refusing symlink target')
        self.verify(self.app)
        paths = [str(self.install / (name + '.dylib')) for name in PATCHES]
        migrated_bytes(executable(self.app).read_bytes(), paths)
        for name in PATCHES:
            load_build(name, self.build)
            library = self.build / (name + '.dylib')
            self.run(['lipo', str(library), '-verify_arch', 'x86_64', 'arm64'])
            self.run(['codesign', '--verify', '--strict', str(library)])

    def install_patches(self):
        self.preflight()
        with self.locked(), self.workspace() as work:
            paths = [str(self.install / (name + '.dylib')) for name in PATCHES]
            source = executable(self.app).read_bytes()
            # Validate every new load command across all slices before any deployment.
            patched = migrated_bytes(source, paths)
            candidate = work / 'candidate.app'
            libs = work / 'libraries'
            libs.mkdir()
            for name in PATCHES:
                self.prepare_library(name, libs)
            self.snapshot_original()
            self.copy_app(self.app, candidate)
            atomic_write(executable(candidate), patched)
            self.sign_candidate(candidate, work)
            self.commit(candidate, work, {p.name: p for p in libs.iterdir()},
                        expected_app_hash=hashlib.sha256(source).hexdigest())
        print('Installed four patches. Restart PDF Expert for UI/account verification.')

    def prepare_library(self, name, directory):
        record = load_build(name, self.build)
        source = self.build / (name + '.dylib')
        target = directory / source.name
        shutil.copy2(source, target)
        if sha(target) != record['binary_sha256']:
            raise RuntimeError('build artifact changed during staging: ' + name)
        self.run(['lipo', str(target), '-verify_arch', 'x86_64', 'arm64'])
        self.run(['codesign', '--force', '--sign', '-', str(target)])
        self.run(['codesign', '--verify', '--strict', str(target)])
        # Signing can change bytes. Track the actual installed artifact, preserving
        # the build hash as a separate link to the locally verified input.
        record['build_binary_sha256'] = record['binary_sha256']
        record['binary_sha256'] = sha(target)
        record['installed_at'] = time.time()
        record['target_app'] = metadata(self.app)
        write_json(directory / (name + '.json'), record)

    def preflight_update(self, name):
        require_patch(name)
        metadata(self.app)
        if self.app.is_symlink() or executable(self.app).is_symlink():
            raise RuntimeError('refusing symlink target')
        if (self.install / (name + '.dylib')).is_symlink() or (self.install / (name + '.json')).is_symlink():
            raise RuntimeError('refusing symlink installed artifact')
        expected = str(self.install / (name + '.dylib'))
        if not all(group.count(expected) == 1 for group in load_paths(executable(self.app).read_bytes())):
            raise RuntimeError(name + ' is not injected exactly once at this path; use full installation')
        load_build(name, self.build)
        library = self.build / (name + '.dylib')
        self.run(['lipo', str(library), '-verify_arch', 'x86_64', 'arm64'])
        self.run(['codesign', '--verify', '--strict', str(library)])

    def backup_module(self, name):
        current = self.install / (name + '.dylib')
        if not current.exists():
            return
        parent = self.backup / 'updates' / name
        parent.mkdir(parents=True, exist_ok=True)
        destination = parent / (str(time.time_ns()) + '-' + sha(current)[:16])
        destination.mkdir()
        for suffix in ('.dylib', '.json'):
            source = self.install / (name + suffix)
            if source.exists():
                shutil.copy2(source, destination / source.name)
        write_json(destination / 'recovery.json', {
            'patch': name, 'binary_sha256': sha(current), 'target_app': metadata(self.app),
            'metadata_present': (destination / (name + '.json')).is_file(),
            'note': 'Previous installed module; not necessarily built from current sources.'})
        print('Previous module backup: ' + str(destination))

    def update_one(self, name):
        self.preflight_update(name)
        before = digest(executable(self.app))
        with self.locked(), self.workspace(libraries_only=True) as work:
            self.preflight_update(name)
            libs = work / 'libraries'
            libs.mkdir()
            self.prepare_library(name, libs)
            self.backup_module(name)
            # No app copy, injection, re-signing or app-directory mutation.
            self.commit(None, work, {p.name: p for p in libs.iterdir()}, expected_app_hash=before)
        print('Updated only ' + name + '; app executable/signature untouched. Restart to load it.')

    def save_original(self):
        metadata(self.app)
        if is_patched(self.app):
            raise RuntimeError('cannot save a patched app as an official original')
        with self.locked():
            self.snapshot_original()

    def restore(self):
        with self.locked(), self.workspace() as work:
            original = self.find_original()
            candidate = work / 'candidate.app'
            self.copy_app(original, candidate)
            self.verify(candidate, official=True)
            self.commit(candidate, work)
        print('Restored complete matching official app; shared dylibs retained for other copies.')

    def check(self):
        info = metadata(self.app)
        print('app: {} ({} build {})'.format(self.app, info['CFBundleShortVersionString'], info['CFBundleVersion']))
        paths = load_paths(executable(self.app).read_bytes())
        healthy = True
        for name in PATCHES:
            expected = str(self.install / (name + '.dylib'))
            identity = status(name, self.build, self.install)
            print('  identity[{}]: version={} installed_sha256={} build_match={} source_match={} recipe_match={}'.format(
                name, identity['project_version'] or 'unknown (untracked)', identity['installed_sha256'],
                identity['matches_build'], identity['matches_source'], identity['matches_recipe']))
            if identity['metadata_valid'] is False:
                print('  metadata INVALID: ' + identity['metadata_error'])
                healthy = False
            present = all(expected in group for group in paths)
            healthy = healthy and present and Path(expected).is_file()
            print('{}: {} ; dylib {}'.format(name, 'injected in all slices' if present else 'MISSING or old path',
                                            'exists' if Path(expected).is_file() else 'MISSING'))
            if Path(expected).is_file():
                try:
                    self.run(['codesign', '--verify', '--strict', expected])
                    self.run(['lipo', expected, '-verify_arch', 'x86_64', 'arm64'])
                except (RuntimeError, subprocess.CalledProcessError) as error:
                    print('  dylib validation failed: ' + str(error))
                    healthy = False
        try:
            self.verify(self.app)
            print('signature: valid (does not prove runtime compatibility)')
        except (RuntimeError, subprocess.CalledProcessError) as error:
            print('signature: INVALID: ' + str(error))
            if isinstance(error, subprocess.CalledProcessError) and error.stderr:
                print(error.stderr.decode(errors='replace').strip())
            healthy = False
        try:
            print('official restore: ' + str(self.find_original()))
        except (RuntimeError, OSError, ValueError) as error:
            print('official restore unavailable: ' + str(error))
        raw = executable(self.app).read_bytes()
        for cls in (b'_TtC14PDF_Expert_DMG14TabContentView', b'RDAKButton'):
            print('{}: {}'.format(cls.decode(), 'found' if cls in raw else 'NOT FOUND'))
        if not healthy:
            raise RuntimeError('one or more installation checks failed; see diagnostics above')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'restore', 'check', 'backup', 'preflight', 'update', 'preflight-update', 'status-json'))
    parser.add_argument('--app', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--backup', required=True)
    parser.add_argument('--install-dir', required=True)
    parser.add_argument('--patch', choices=PATCHES)
    args = parser.parse_args()
    deployment = Deployment(args.app, args.build, args.backup, args.install_dir)
    if args.action in ('update', 'preflight-update'):
        if not args.patch:
            parser.error('--patch is required for module update')
        method = deployment.update_one if args.action == 'update' else deployment.preflight_update
        method(args.patch)
        return
    if args.action == 'status-json':
        print(json.dumps(identity_report(deployment.app, deployment.build, deployment.install), indent=2))
        return
    getattr(deployment, {'install': 'install_patches', 'restore': 'restore', 'check': 'check', 'backup': 'save_original', 'preflight': 'preflight'}[args.action])()


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.decode(errors='replace'), file=sys.stderr)
        sys.exit(1)
