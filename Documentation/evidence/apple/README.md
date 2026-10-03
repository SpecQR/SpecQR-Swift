# Apple validation — 2026-10-03

This directory preserves the initial Command Line Tools validation phase.
Its supported macOS checks passed after two narrow portability fixes, while
the original XCTest suite was blocked by the tools available at that time.

The user subsequently authorized official Xcode installation. With Xcode 27.0,
the original macOS debug/release suites each passed 54 XCTest +2 Swift Testing
methods; the independent consumer also passed again, and all eight device-SDK
source-compile lanes passed. Those later results are recorded separately in
[Xcode evidence](../xcode/README.md). The initial failures below remain historical
evidence. Later iOS 27.0 simulator debug/release runs also passed 54 XCTest +2
Swift Testing methods each, with zero failures/skips, using the supported
Vision revision 2 and CPU configuration described below. The candidate remains
unpublished and physical-device/camera/print checks remain separate gates.

## Environment during the initial CLT phase

- Host: arm64 macOS 27.0, build 26A428.
- Existing Command Line Tools: 27.0.0.0.1787197235.
- Apple Swift: 6.4, swiftlang-6.4.0.33.1, clang-2100.3.33.1.
- Executed SDK: macOS 27.0, build 26A5419a. macOS 26.5 is also installed but was not used.
- Bundled Swift Testing: 2078. The independent test package targets macOS 14
  to match this Testing framework; the library and Basic consumer target macOS 13.
- Full Xcode, XCTest, iOS/tvOS/watchOS SDKs and simulator tools/runtimes were
  unavailable. `environment.log` records the available toolchain checks.
- No SDK, Xcode, toolchain or external test dependency was installed during
  this initial CLT phase. All source/build work used an isolated directory.

## Actual execution and compilation

| Lane | Result | Evidence |
|---|---|---|
| arm64 library and CLI, debug/release | Builds passed | `build-debug.log`, `build-release.log` |
| Basic source-package public consumer, debug/release | Builds and executions passed | `consumer-debug.log`, `consumer-release.log` |
| Independent Swift Testing consumer, debug | 10 tests in 2 suites passed, 0 failures | `validation-debug.log` |
| Independent Swift Testing consumer, release | 10 tests in 2 suites passed, 0 failures | `validation-release.log` |
| Intel macOS 13 library | x86_64 cross-compilation passed; no Intel execution | `build-intel-cross.log` |
| Original package XCTest, debug/release | Both attempts blocked at compilation by missing XCTest | `test-debug.log`, `test-release.log` |

The independent tests use only public SpecQR APIs, real Swift Testing macros,
and unconditional CoreGraphics/ImageIO/Vision imports. They do not substitute
a fake XCTest module or suppress missing frameworks as successful skips.

Each configuration executes:

- Core Graphics straight RGBA8 provider bytes, width/height/stride/alpha,
  interpolation flags, retained storage after an autorelease pool, and drawing.
- Four ImageIO decodes of actual generated PNG data, checking every output
  pixel across two margins and two scales.
- Seventeen actual Vision decode checks: five ordinary/Unicode strings through
  both CGImage and PNG, three GS1 literal-percent/separator strings through both
  paths, and one explicitly escaped low-level FNC1 symbol. UTF-8 bytes are
  compared to detect normalization or payload loss.
- Twelve input/option combinations for the two high-level FNC1 forms with
  optimization on/off, exact matrix/reference equality, planning agreement,
  safe byte mode and rejection of ambiguous explicit alphanumeric input.
- Invalid color/geometry/overflow/resource-budget checks and a Version 40 image.
- Structured Append header, byte ranges, shuffled merge, parity and corruption
  checks; 32 concurrent Core Graphics renders and value isolation.
- The original 1,411 GS1 fixtures and 22 Structured Append fixtures, including
  exact matrices and split metadata. These case counts are inside the 10 test
  methods; they are not separate methods to add to the total.

Vision did not validate FNC1-second application-indicator metadata or Structured
Append image metadata in this lane. The corrected-source Linux ZXing reports
provide separate synthetic decoder evidence for those features. No physical
camera, printed symbol, certification or scanner-performance claim is made.

## Fixes and independent review

1. `Examples/Basic/Package.swift` now declares macOS 13. Before the change, its
   default macOS 12 target could not depend on SpecQR's macOS 13 product. The
   exact failure is in `consumer-before-fix.log`; both configurations now run.
2. `Rendering.swift` widens `dimension` to `Int64` before comparing it with the
   53-bit maximum. The prior integer literal cannot be represented by a 32-bit
   `Int`, relevant to watchOS arm64_32. `int32-before.log` reproduces the compile
   failure and `int32-after.log` accompanies the successful corrected probe.
   `watchos-target-macros.log` confirms arm64_32's 32-bit pointer properties; its
   incompatible macOS-sysroot warning is retained. This is not a watchOS build.

Independent adapter review found no verified Core Graphics implementation
defect: straight alpha, provider ownership and row stride agree with the local
SDK contract. The original Apple XCTest is narrow and gated on Vision; the
separate consumer adds the broader checks above without changing that suite.
The high-level GS1/FNC1 literal-percent safety correction is preserved.

`runtime-and-tests.diff` contains the exact source/example/new validation
changes against the imported candidate. `runtime-source-sha256.txt` and
`executed-binaries-sha256.txt` identify the tested source and executables.
`../mac-fix-linux-validation/` contains the same corrected source's successful
Swift 6.0.3/6.4 debug/release, consumer and full external aggregate reruns.
The imported archive was byte-verified; 31 runtime/test manifest entries and
both patched files match locally (`linux-evidence-check.log`). Earlier Linux
evidence elsewhere remains historical and has not been overwritten.

## Reproduction and setup diagnostics

From the package root, run `./Scripts/verify-apple.sh` for both independent
configurations, or pass `debug` / `release`. The recorded invocation supplied
task-local `SPECQR_APPLE_BUILD_DIR` and `SPECQR_APPLE_CACHE_DIR`; the default
uses `.build`. `bash -n` and strict Swift formatting passed.

The installed CLT's SwiftPM default omitted Testing macro and dynamic-library
paths. The script uses the existing selected toolchain paths explicitly.
Initial macro/runtime-path failures, a fixture-port compile correction, and a
native-build-system attempt are preserved as `validation-initial-*`,
`validation-swiftbuild-plugin.log` and `validation-native-framework-path.log`.
They are not passing test runs. Initial sandbox cache/dSYM failures were
resolved using local caches and authorized native developer-tool execution.
Successful builds retain CLT linker warnings about nonexistent default search
directories; no zero-warning claim is made for this host.

## Later completion and outstanding gates

The initial environment above had no Xcode candidate in its narrow
app-directory and Spotlight searches. After explicit user authorization,
official Xcode 27.0 was installed and retained. The later original macOS suite
runs and real iOS/tvOS/watchOS SDK source compiles have now completed without
additional library source changes. See [Xcode evidence](../xcode/README.md).

The SDK object minimums are iOS 16 and tvOS 16 on arm64 and watchOS 9 on
arm64_32, confirming the earlier integer-width fix with the real watchOS SDK.
The additional watchOS arm64 lanes emitted minimum watchOS 26, so they are not
watchOS 9 arm64 results. These are compile-only results; they do not establish
device/simulator execution, linking, deployment or signing.

iOS 27.0 (24A434), iPhone 17 arm64 simulator execution is now complete:
debug/release each passed 54 XCTest +2 Swift Testing methods, with zero failures
and zero skips. The Apple test now selects revision 2 and a supported CPU
device only on the iOS simulator. Its default-size SpecQR image, actual Vision
perform call and exact payload assertion remain unchanged; macOS uses the
default request. Revision 2 is deprecated but supported by this runtime.

This does not establish default-revision simulator support. Default revision 4
initially threw Vision Code 9, and the independent 40-request control probe
found zero observations for revisions 3/4 on both SpecQR and Apple CoreImage QR
images. Revision 1 and revision 2 with CPU recovered the payload. The probe's
19 exact matches, 20 empty results and one inference error remain recorded in
[Vision probe evidence](../xcode/vision-probe/README.txt); its process exit 0
only confirms diagnostic completion. No production renderer defect was
established, and production source remains covered by the earlier Linux reruns.

Declared deployment-minimum OS execution, other CPU/device runs and physical
camera/print behavior remain separate checks. Remote CI has not been run.

No repository creation, push, PR, tag, release or publication occurred.
