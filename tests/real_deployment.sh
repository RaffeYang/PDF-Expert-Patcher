#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tools/env.sh"
export PATH="$(dirname "$PE_CLANG"):$PATH"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pepatch-integration.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/PDF Expert.app"
INSTALL="$WORK/lib"
mkdir -p "$APP/Contents/MacOS"
"$PE_CLANG" -isysroot "$PE_SDK" -arch x86_64 -arch arm64 -Wl,-headerpad,0x1000 \
  "$ROOT/tests/TestExecutable.c" -o "$APP/Contents/MacOS/PDF Expert"
"$PE_PYTHON" - "$APP" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
 'CFBundleIdentifier': 'com.readdle.PDFExpert-Mac', 'CFBundleShortVersionString': '0.0.test',
 'CFBundleVersion': '1', 'CFBundleExecutable': 'PDF Expert', 'CFBundlePackageType': 'APPL'}))
PY
# Model a legacy patched bundle without a full official backup.
"$PE_PYTHON" "$ROOT/tools/inject_lc.py" "$APP/Contents/MacOS/PDF Expert" /old/TabPatch.dylib
codesign --force --sign - "$APP"
for pass in 1 2; do
  "$PE_PYTHON" "$ROOT/tools/deploy.py" install --app "$APP" \
    --build "${PEPATCH_BUILD_DIR:-$ROOT/build}" --backup "$WORK/backup" --install-dir "$INSTALL"
done
"$PE_PYTHON" "$ROOT/tools/deploy.py" check --app "$APP" \
  --build "${PEPATCH_BUILD_DIR:-$ROOT/build}" --backup "$WORK/backup" --install-dir "$INSTALL"
"$PE_PYTHON" - "$ROOT/tools" "$APP/Contents/MacOS/PDF Expert" "$INSTALL" <<'PY'
import pathlib, sys
sys.path.insert(0, sys.argv[1])
from inject_lc import load_paths
from deploy import PATCHES
for paths in load_paths(pathlib.Path(sys.argv[2]).read_bytes()):
    for name in PATCHES:
        assert paths.count(str(pathlib.Path(sys.argv[3]) / (name + '.dylib'))) == 1
    assert '/old/TabPatch.dylib' not in paths
PY
# Real module-only build/update: unselected module metadata and app bytes stay identical.
"$PE_PYTHON" - "$ROOT" "$APP" "$INSTALL" "${PEPATCH_BUILD_DIR:-$ROOT/build}" "$WORK" <<'PYTEST'
import hashlib, json, os, pathlib, subprocess, sys
root, app, install, build, work = map(pathlib.Path, sys.argv[1:])
def file_state(path):
    return (hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns)
untouched = {path: file_state(path) for name in ('TabPatch', 'ToolbarPatch', 'KeychainFix')
             for path in (build / (name + '.dylib'), build / (name + '.json'),
                          install / (name + '.dylib'), install / (name + '.json'))}
app_state = {p: file_state(p) for p in app.rglob('*') if p.is_file()}
env = dict(os.environ, PEPATCH_BUILD_DIR=str(build))
subprocess.run([str(root / 'patch.sh'), '--build', 'SidebarPatch'], env=env, check=True)
subprocess.run([sys.executable, str(root / 'tools/deploy.py'), 'update', '--patch', 'SidebarPatch',
               '--app', str(app), '--build', str(build), '--backup', str(work / 'backup'),
               '--install-dir', str(install)], check=True)
assert all(file_state(p) == state for p, state in untouched.items()), 'unselected artifact changed'
assert {p: file_state(p) for p in app.rglob('*') if p.is_file()} == app_state, 'module update modified app'
record = json.loads((install / 'SidebarPatch.json').read_text())
assert record['project_version'] == (root / 'VERSION').read_text().strip()
assert record['binary_sha256'] == file_state(install / 'SidebarPatch.dylib')[0]
assert list((work / 'backup/updates/SidebarPatch').glob('*/SidebarPatch.dylib'))
print('REAL SINGLE-MODULE BUILD/UPDATE PASSED')
PYTEST
if "$PE_PYTHON" "$ROOT/tools/deploy.py" restore --app "$APP" \
    --build "${PEPATCH_BUILD_DIR:-$ROOT/build}" --backup "$WORK/backup" --install-dir "$INSTALL"; then
  echo 'FAIL: restore without official snapshot unexpectedly succeeded' >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
echo 'REAL DEPLOYMENT INTEGRATION PASSED'
