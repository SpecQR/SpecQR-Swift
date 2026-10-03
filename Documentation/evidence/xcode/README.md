# Xcode validation — 2026-10-03

This phase followed the initial Command Line Tools checks in `../apple/`.
Official stable Xcode was installed from Apple's App Store for this validation. Production
source, the example and validation script remained byte-identical to the
earlier Mac-corrected candidate. One iOS-simulator-only test configuration was
added as described below; the corrected production source's Linux reruns
still apply.

## Environment and installation

- Host: arm64 macOS 27.0 (26A428).
- Xcode 27.0 (27A266a), `/Applications/Xcode.app`.
- Apple Swift 6.4, swiftlang-6.4.0.34.1, clang-2100.3.34.1.
- Bundled Swift Testing 2084.
- macOS, iOS, tvOS and watchOS SDKs 27.0; exact SDK build versions are
  recorded in `environment.log` and `sdk/environment.log`.
- Commands scoped `DEVELOPER_DIR` to this Xcode. The global developer
  selection was not changed. Xcode's External Agent Access choice was not
  confirmed or changed. No credential, security setting or legal-acceptance
  command was supplied by the agent.
- iOS simulator runtime: 27.0 (24A434), arm64 only. Optional tvOS,
  watchOS and visionOS runtimes were not downloaded.
- Only task-owned build storage is eligible for cleanup. Xcode is retained.

## Completed execution

| Lane | Result | Evidence |
|---|---|---|
| Original SwiftPM macOS debug, final test source | 54 XCTest + 2 Swift Testing, zero failures | `test-debug-final.log` |
| Original SwiftPM macOS release, final test source | 54 XCTest + 2 Swift Testing, zero failures | `test-release-final.log` |
| Public source-package Basic consumer, release | Build and execution passed | `consumer-release.log` |
| Independent Apple consumer, debug and release | 10 methods in 2 suites each, zero failures | `apple-validation/` |
| Device SDK library builds | All eight debug/release lanes passed | `sdk/` |
| iOS 27 simulator debug | 54 XCTest + 2 Swift Testing, zero failures/skips | `simulator-debug-test.log`, `simulator-debug-result-summary.json` |
| iOS 27 simulator release | 54 XCTest + 2 Swift Testing, zero failures/skips | `simulator-release-test.log`, `simulator-release-result-summary.json` |

The original macOS suites actually executed
`ApplePlatformTests.testCoreGraphicsAndVisionDecode`. The independent consumer
executed 17 Vision decode/payload checks, 4 ImageIO full-pixel PNG roundtrips,
1,411 GS1 fixtures and 22 Structured Append fixtures per configuration.
Fixture and assertion counts are contained in the method totals and overlap
between configurations; they must not be added as unique test methods.

The iOS and tvOS device objects target minimum OS 16.0. The watchOS
`arm64_32` objects target minimum OS 9.0. Xcode accepts an arm64 watchOS 9
requested triple but emits minimum OS 26.0 for that architecture; the extra
arm64 lane therefore establishes watchOS 26 compilation only. Object load
commands and hashes in `sdk/` establish this distinction. These are actual
SDK compilations, not execution on those operating-system versions.

## Simulator execution and decoder configuration

Both complete suites ran on the dedicated iPhone 17 simulator, iOS 27.0
(24A434), arm64. Original images, fixture assertions and decoded-payload
equality remain intact. Public results are the sanitized logs and `simulator-*-result-summary.json` files.
Raw Xcode result bundles are retained privately and excluded from this repository.
The library's iOS minimum is 16; this toolchain's test framework raises the
test bundle minimum to 17. Neither minimum OS was executed on this host.

The default Vision request initially threw Code 9 (could not create inference
context). Selecting a supported CPU device allowed inference, but revisions
3 and 4 returned no observations. An independent native simulator probe made
40 requests covering SpecQR's unchanged default 296-pixel image, a larger
image, Apple's own Core Image QR encoder, and normalized pixel storage.
Revisions 3/4 missed both encoders; revision 2 with CPU selection decoded every
probe input to the exact payload. See `vision-probe/README.txt` and its complete
positive/negative results. This did not identify a SpecQR renderer defect.

`ApplePlatformTests.swift` now selects the supported, deprecated Vision
revision 2 and CPU devices only for iOS simulators. It still performs real
Vision decoding and asserts the exact original payload. No tests are skipped,
no inference errors are swallowed, and the production adapter is unchanged.
Other platforms retain the default Vision request. The exact change is in
`simulator-test-configuration.diff`; the initial unsuccessful CPU-only
candidate is separately retained. Passing configured simulator tests do not
establish that the default revision 4 simulator backend works.

The `SpecQR` product scheme initially produced an empty test configuration;
`simulator-build-for-testing.log` is library compile evidence only. The
`SpecQR-Package` scheme includes the real test target and fixtures. Release
Xcode tests require `ENABLE_TESTABILITY=YES` for existing `@testable` imports;
the initial configuration failure is retained.

The first simulator runner timed out before executing any tests across a host
connection interruption. Its sampled bundle-directory open was delayed but
eventually succeeded. No explicit denial targeting the bundle was found.
The retry ran from the original path, without moving files or changing privacy
settings. `simulator-initial-diagnosis.txt` and the initial result summary retain
the relevant outcome. Raw process/session diagnostics are excluded from the public copy. Initial runner/Vision failures are not passing test runs.

## Reproduction

From the package root with full Xcode selected for the command:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift test -c release
swift run --package-path Examples/Basic -c release
./Scripts/verify-apple.sh
```

The recorded macOS commands used `--disable-sandbox -j 2`, task-local scratch,
cache/config/security paths and `CLANG_MODULE_CACHE_PATH`; native developer
tool execution was authorized to avoid sandbox interference with Apple's
build and simulator services. `commands.txt` records concrete invocations.
`executed-build-binaries-sha256.txt` records the built test/consumer binaries.
`sdk/README.txt` and `apple-validation/README.txt` reproduce the other lanes.

For simulator reproduction, create a fresh device from the installed runtime
and use its returned identifier with the `SpecQR-Package` scheme. The disposable
device identifier in the historical commands was deleted after saving results.
Run `xcodebuild ... test` for Debug and Release, using `ENABLE_TESTABILITY=YES`
for Release and the same destination settings recorded in `commands.txt`.
`summary.json` consolidates final results and the known simulator limitation.

## Remaining scope limits

No deployment-minimum OS, Intel execution, tvOS/watchOS simulator execution,
physical device/camera/print test, certification or remote CI was performed.
Default Vision revisions 3/4 remain a known limitation of the tested iOS 27
simulator environment; no claim is made about their behavior on physical iOS.
Actual QR decoder evidence does not certify every scanner's metadata behavior.
These logs describe validation before the initial repository publication.
No versioned tag/release, physical-device validation or remote-CI result is implied by them.
