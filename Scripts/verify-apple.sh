#!/usr/bin/env bash
set -euo pipefail

# Independent Swift Testing consumer lane; does not replace root XCTest tests.
root="$(cd "$(dirname "$0")/.." && pwd)"
developer="$(xcode-select -p)"
compiler="$(xcrun --find swiftc)"
plugins="$(dirname "$compiler")/../lib/swift/host/plugins/testing"
scratch="${SPECQR_APPLE_BUILD_DIR:-$root/.build/apple-validation}"
cache="${SPECQR_APPLE_CACHE_DIR:-$root/.build/apple-validation-support}"
export CLANG_MODULE_CACHE_PATH="$cache/clang-cache"
arguments=(--package-path "$root/Scripts/apple-validation" --scratch-path "$scratch"
   --cache-path "$cache/cache" --config-path "$cache/config" --security-path "$cache/security"
   --disable-sandbox --disable-xctest -j 2)

# Some CLT distributions omit these bundled Testing paths from SwiftPM's defaults.
if [[ -d "$plugins" ]]; then
   arguments+=(-Xswiftc -plugin-path -Xswiftc "$plugins")
fi
if [[ -d "$developer/Library/Developer/Frameworks/Testing.framework" ]]; then
   arguments+=(-Xlinker -rpath -Xlinker "$developer/Library/Developer/Frameworks")
fi
if [[ -f "$developer/Library/Developer/usr/lib/lib_TestingInterop.dylib" ]]; then
   arguments+=(-Xlinker -rpath -Xlinker "$developer/Library/Developer/usr/lib")
fi

configurations=("$@")
if [[ ${#configurations[@]} -eq 0 ]]; then
   configurations=(debug release)
fi
for configuration in "${configurations[@]}"; do
   if [[ "$configuration" != debug && "$configuration" != release ]]; then
      echo "Usage: $0 [debug|release ...]" >&2
      exit 2
   fi
   echo "Independent Apple Swift Testing consumer: $configuration"
   swift test "${arguments[@]}" -c "$configuration"
done
