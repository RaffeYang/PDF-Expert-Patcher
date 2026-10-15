#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tools/env.sh"
export PEPATCH_BUILD_DIR="${PEPATCH_BUILD_DIR:-$ROOT/build}"
BUILD_DIR="$PEPATCH_BUILD_DIR"
"$ROOT/tools/build.sh"
"$PE_PYTHON" -m unittest discover -s "$ROOT/tests" -p 'test_*.py'
for name in TestHost SidebarPatchTest ToolbarPatchTest ContextMenuPatchTest HookChainTest KeychainFixTest; do
  "$PE_CLANG" -isysroot "$PE_SDK" -fobjc-arc -I"$ROOT/src/vendor" \
    -framework Cocoa -framework Security "$ROOT/tests/$name.m" -o "$BUILD_DIR/$name"
done
"$BUILD_DIR/TestHost" "$BUILD_DIR/TabPatch.dylib"
"$BUILD_DIR/SidebarPatchTest" "$BUILD_DIR/SidebarPatch.dylib"
"$BUILD_DIR/ToolbarPatchTest" "$BUILD_DIR/ToolbarPatch.dylib"
"$BUILD_DIR/ContextMenuPatchTest" "$BUILD_DIR/ToolbarPatch.dylib"
TOOLBARPATCH_DISABLE=1 "$BUILD_DIR/ContextMenuPatchTest" "$BUILD_DIR/ToolbarPatch.dylib"
for order in forward reverse; do
  libs=("$BUILD_DIR/SidebarPatch.dylib" "$BUILD_DIR/ToolbarPatch.dylib")
  if [[ "$order" == reverse ]]; then libs=("${libs[1]}" "${libs[0]}"); fi
  "$BUILD_DIR/HookChainTest" "${libs[@]}"
  SIDEBARPATCH_DISABLE=1 TOOLBARPATCH_DISABLE=1 "$BUILD_DIR/HookChainTest" "${libs[@]}"
  SIDEBARPATCH_DISABLE=1 "$BUILD_DIR/HookChainTest" "${libs[@]}"
  TOOLBARPATCH_DISABLE=1 "$BUILD_DIR/HookChainTest" "${libs[@]}"
done
"$BUILD_DIR/KeychainFixTest"
KEYCHAINFIX_DISABLE=1 "$BUILD_DIR/KeychainFixTest"
KEYCHAINFIX_DEBUG=1 "$BUILD_DIR/KeychainFixTest" > "$BUILD_DIR/KeychainFix.debug.log" 2>&1
if grep -E 'test-service|test-sensitive-account|test-sensitive-value|3L68KQB4HG' "$BUILD_DIR/KeychainFix.debug.log" >/dev/null; then
  echo 'FAIL: keychain diagnostic leaked a test identifier/value' >&2
  exit 1
fi
echo 'KEYCHAIN DIAGNOSTIC PRIVACY CHECK PASSED'
"$ROOT/tests/real_deployment.sh"
for script in "$ROOT/patch.sh" "$ROOT/tools/"*.sh "$ROOT/tests/"*.sh; do bash -n "$script"; done
echo 'ALL CHECKS PASSED (headless tests; real app UI/account acceptance still required)'
