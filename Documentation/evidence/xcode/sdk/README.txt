Apple device-SDK compile evidence — 2026-10-03

All eight compile-only lanes passed. No library/package source files changed.
Each lane compiled the complete SpecQR library target, including AppleGraphics,
into 18 Mach-O objects and one SpecQR.swiftmodule. Object/module SHA-256 values
and all 18 input-source SHA-256 values are retained in results.json.

Requested target                 Configurations    Verified object minimum OS
arm64-apple-ios16.0               debug + release   iOS 16.0
arm64-apple-tvos16.0              debug + release   tvOS 16.0
arm64_32-apple-watchos9.0         debug + release   watchOS 9.0
arm64-apple-watchos9.0            debug + release   watchOS 26.0

Important: Xcode's Swift compiler accepted the requested watchOS arm64 target,
but its generated Mach-O LC_BUILD_VERSION uses minos 26.0. That lane is therefore
additional watchOS 26 arm64 compilation coverage, not a watchOS 9 arm64 result.
The watchOS 9 minimum is verified by the arm64_32 lanes, which emitted
arm64_32_v8 objects with minos 9.0. This also validates the existing 32-bit-safe
render-limit change against the real watchOS SDK.

Toolchain:
- Xcode 27.0, build 27A266a
- Apple Swift 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
- iOS SDK 27.0, build 24A430
- tvOS SDK 27.0, build 24J360
- watchOS SDK 27.0, build 24R360
- Host: arm64 macOS 27.0, build 26A428

Evidence:
- environment.log: native toolchain/system version commands and SDK inventory
- results.json: exact commands, exit statuses, durations, SDK metadata and hashes
- <lane>.log: full verbose compiler/SwiftPM output
- <lane>-objects.log: every object's file architecture and AppleGraphics object's
  complete Mach-O load-command inspection (including platform/minos/sdk)
- initial-sandbox-block.log: first SwiftPM invocation was denied at nested
  sandbox setup. The authorized native developer-tool retry passed all lanes.
- run-sdk-builds.py: reproducible sequential task-local compile/check/cleanup

Reproduce from any working directory with full Xcode installed at the recorded
location (no network dependency, no signing required):
  python3 Documentation/evidence/xcode/sdk/run-sdk-builds.py
Run that relative path from the SpecQR package root, or use its absolute path.

The process-local DEVELOPER_DIR selected Xcode; global developer settings were
not changed. Builds used SwiftPM's native compile-only backend, -j 2, disabled
indexing and task-local scratch/cache locations. The backend prints its known
deprecation warning. No library source compile diagnostics were reported.

After collecting evidence, only the script's .build-xcode-sdk and
.build-xcode-sdk-support directories were removed. About 15 GiB remained free.

These are genuine Apple SDK source compiles, not device/simulator execution,
link/deploy/signing tests, minimum-OS runtime tests, or physical scanner tests.
No Apple platform library runtime execution is claimed by this evidence set.
