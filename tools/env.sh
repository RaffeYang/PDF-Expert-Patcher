#!/bin/bash
# Shared tool discovery; overrides support non-default Xcode/CLT installations.
PE_DEVELOPER="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
PE_CLANG="${CLANG:-$PE_DEVELOPER/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang}"
if [[ ! -x "$PE_CLANG" ]]; then PE_CLANG="$(/usr/bin/xcrun --find clang)"; fi
PE_SDK="${SDKROOT:-$PE_DEVELOPER/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
if [[ ! -d "$PE_SDK" ]]; then PE_SDK="$(/usr/bin/xcrun --show-sdk-path)"; fi
PE_PYTHON="${PYTHON:-$PE_DEVELOPER/usr/bin/python3}"
if [[ ! -x "$PE_PYTHON" ]]; then PE_PYTHON="$(command -v python3)"; fi
