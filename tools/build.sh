#!/bin/bash
# Build all modules or only the explicitly selected module(s).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tools/env.sh"
BUILD_DIR="${PEPATCH_BUILD_DIR:-$ROOT/build}"
if [[ $# == 0 ]]; then set -- TabPatch SidebarPatch ToolbarPatch KeychainFix; fi
# Validate the complete request before creating or replacing output files.
for name in "$@"; do
  case "$name" in TabPatch|SidebarPatch|ToolbarPatch|KeychainFix) ;; *) echo "ERROR: unknown patch: $name" >&2; exit 2 ;; esac
done
mkdir -p "$BUILD_DIR"
STAGE=''
cleanup() { if [[ -n "$STAGE" && -d "$STAGE" ]]; then rm -rf "$STAGE"; fi; }
trap cleanup EXIT
for name in "$@"; do
  STAGE="$(mktemp -d "$BUILD_DIR/.build-$name.XXXXXX")"
  expected_source="$("$PE_PYTHON" "$ROOT/tools/provenance.py" source "$name")"
  extra=()
  if [[ "$name" == KeychainFix ]]; then extra=(-I"$ROOT/src/vendor" "$ROOT/src/vendor/fishhook.c"); fi
  "$PE_CLANG" -isysroot "$PE_SDK" -arch x86_64 -arch arm64 \
    -mmacosx-version-min=11.0 -dynamiclib -fobjc-arc -Wall -Wextra \
    -framework Cocoa -framework Security -install_name "@rpath/$name.dylib" \
    "$ROOT/src/$name.m" ${extra[@]+"${extra[@]}"} -o "$STAGE/$name.dylib"
  "$(dirname "$PE_CLANG")/lipo" "$STAGE/$name.dylib" -verify_arch x86_64 arm64
  /usr/bin/codesign --force --sign - "$STAGE/$name.dylib"
  /usr/bin/codesign --verify --strict "$STAGE/$name.dylib"
  "$PE_PYTHON" "$ROOT/tools/provenance.py" write "$name" --build "$STAGE" --expected-source "$expected_source"
  # Replace directory entries (also handles artifacts previously built with sudo).
  mv -f "$STAGE/$name.dylib" "$BUILD_DIR/$name.dylib"
  mv -f "$STAGE/$name.json" "$BUILD_DIR/$name.json"
  cleanup
  STAGE=''
  echo "Built universal $name with version/source/binary metadata"
done
