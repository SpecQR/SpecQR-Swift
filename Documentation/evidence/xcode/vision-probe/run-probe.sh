#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$root"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
scratch="$root/.build-xcode-vision-probe"
products="$root/.build-xcode-simulator/Build/Products/Debug-iphonesimulator"
evidence="$root/Documentation/evidence/xcode/vision-probe"
device="${SPECQR_PROBE_SIMULATOR:?Set SPECQR_PROBE_SIMULATOR to an available simulator UDID}"
mkdir -p "$scratch"
# Existing object was built with coverage instrumentation, so link its runtime.
xcrun --sdk iphonesimulator swiftc -sdk "$SDKROOT" -target arm64-apple-ios17.0-simulator \
   -profile-generate -profile-coverage-mapping -I "$products" \
   -module-cache-path "$scratch/module-cache" "$evidence/VisionProbe.swift" \
   "$products/SpecQR.o" -o "$scratch/VisionProbe" > "$evidence/compile.log" 2>&1
SIMCTL_CHILD_LLVM_PROFILE_FILE=/dev/null xcrun simctl spawn "$device" \
   "$scratch/VisionProbe" > "$evidence/simulator.log" 2>&1
