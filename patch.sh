#!/bin/bash
# Daily CLI. Full app install and module-only updates are separate operations.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${PDF_EXPERT_APP:-/Applications/PDF Expert.app}"
BUILD_DIR="${PEPATCH_BUILD_DIR:-$ROOT/build}"
BACKUP_DIR="${PEPATCH_BACKUP_DIR:-$ROOT/backup}"
INSTALL_DIR="${PEPATCH_INSTALL_DIR:-$HOME/Library/PEPatch}"
usage() {
  cat <<'USAGE'
Usage: ./patch.sh                         Build/install all four patches
       ./patch.sh --build [PATCH]        Build all, or one patch only
       ./patch.sh --update PATCH         Build/update one already-injected dylib
       ./patch.sh --test                 Full automated/synthetic test suite
       ./patch.sh --check                Read-only signatures/architecture/identity
       ./patch.sh --status-json          Read-only machine-readable identity
       ./patch.sh --record-compatibility Capture observation; manual results pending
       ./patch.sh --restore              Restore complete matching official app
       ./patch.sh --backup-original      Save complete official app snapshot
PATCH: TabPatch | SidebarPatch | ToolbarPatch | KeychainFix
USAGE
}
valid_patch() {
  case "$1" in TabPatch|SidebarPatch|ToolbarPatch|KeychainFix) return 0 ;; *) echo "ERROR: unknown patch: $1" >&2; return 1 ;; esac
}
selected=''
case "${1:-}" in
  --help) [[ $# == 1 ]] || { usage >&2; exit 2; }; usage; exit 0 ;;
  --build)
    [[ $# -le 2 ]] || { usage >&2; exit 2; }
    if [[ $# == 2 ]]; then valid_patch "$2" || exit 2; exec "$ROOT/tools/build.sh" "$2"; fi
    exec "$ROOT/tools/build.sh" ;;
  --update)
    [[ $# == 2 ]] || { usage >&2; exit 2; }
    valid_patch "$2" || exit 2
    selected="$2"; action=update ;;
  --test) [[ $# == 1 ]] || { usage >&2; exit 2; }; exec "$ROOT/tools/test.sh" ;;
  --check) action=check ;;
  --status-json) action=status-json ;;
  --record-compatibility) action=record ;;
  --restore) action=restore ;;
  --backup-original) action=backup ;;
  '') [[ $# == 0 ]] || { usage >&2; exit 2; }; action=install ;;
  *) usage >&2; exit 2 ;;
esac
if [[ "$action" != update && $# -gt 1 ]]; then usage >&2; exit 2; fi
source "$ROOT/tools/env.sh"
export PATH="$(dirname "$PE_CLANG"):$PATH"
[[ -f "$APP_PATH/Contents/MacOS/PDF Expert" ]] || { echo "ERROR: executable missing: $APP_PATH" >&2; exit 1; }
if [[ "$action" == record ]]; then
  mkdir -p "$BUILD_DIR"
  exec "$PE_PYTHON" "$ROOT/tools/compatibility.py" --app "$APP_PATH" --build "$BUILD_DIR" \
    --install-dir "$INSTALL_DIR" --output "$BUILD_DIR/compatibility-observation.json"
fi
for tool in codesign lipo ditto pgrep osascript; do
  command -v "$tool" >/dev/null || { echo "ERROR: required tool missing: $tool" >&2; exit 1; }
done
args=(--app "$APP_PATH" --build "$BUILD_DIR" --backup "$BACKUP_DIR" --install-dir "$INSTALL_DIR")
if [[ "$action" == install ]]; then
  "$ROOT/tools/build.sh"
  "$PE_PYTHON" "$ROOT/tools/deploy.py" preflight "${args[@]}"
elif [[ "$action" == update ]]; then
  "$ROOT/tools/build.sh" "$selected"
  args+=(--patch "$selected")
  "$PE_PYTHON" "$ROOT/tools/deploy.py" preflight-update "${args[@]}"
fi
if [[ "$action" == install || "$action" == restore || "$action" == update ]]; then
  # A sandbox/process-inspection failure is not evidence that the app is closed.
  if pgrep -x 'PDF Expert' >/dev/null; then
    osascript - "$APP_PATH" <<'APPLESCRIPT'
on run argv
  tell application (item 1 of argv) to quit
end run
APPLESCRIPT
  else
    rc=$?
    [[ "$rc" == 1 ]] || { echo 'ERROR: cannot inspect app process; no deployment performed.' >&2; exit 1; }
  fi
  for attempt in 1 2 3 4 5; do
    if pgrep -x 'PDF Expert' >/dev/null; then sleep 1; else
      rc=$?
      [[ "$rc" == 1 ]] || { echo 'ERROR: cannot confirm app exited.' >&2; exit 1; }
      break
    fi
  done
  if pgrep -x 'PDF Expert' >/dev/null; then
    echo 'ERROR: PDF Expert is still running; save documents and quit all copies before retrying.' >&2
    exit 1
  else
    rc=$?
    [[ "$rc" == 1 ]] || { echo 'ERROR: cannot confirm app exited.' >&2; exit 1; }
  fi
fi
exec "$PE_PYTHON" "$ROOT/tools/deploy.py" "$action" "${args[@]}"
