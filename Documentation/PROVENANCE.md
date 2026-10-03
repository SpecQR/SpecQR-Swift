# Provenance and licensing

## Canonical behavior reference

- Project: SpecQR/SpecQR (connected GitHub identity: SpecQR)
- Source: https://github.com/SpecQR/SpecQR
- Exact commit: `15ad15e5c770ea0e39072f8f88b2733018f02ffd`
- Commit date: 2026-08-02
- package.json: `3.0.0-rc.2`
- License: MIT, copyright SpecQR contributors; LICENSE retained verbatim

The Swift implementation was newly authored from the user's requested behavior
and the actual pinned upstream source, documentation and test vectors. It does
not call a third-party QR encoder, Core Image, a web view, or JavaScript. QR
capacity/block-layout constants describe the same Model 2 tables as the upstream
project. No paid ISO specification text is included.

Kanji mapping uses a generated, deterministic mapping of the QR-valid Shift_JIS
ranges following the upstream WHATWG TextDecoder mapping and first-hit rule.
The generator, mapping count and implementation source are retained alongside
the Swift implementation. No platform codec is used at runtime.

Previous Swift archives could not be retrieved through the available file
materialization route. They were left untouched and were not treated as verified
source or as passing tests for this implementation.

## Test-only references

The external checks use the pinned upstream's package-lock.json:

- nayuki-qr-code-generator 1.8.0 (MIT), independently checks exact fixed-mask matrices
- jsqr 1.4.0 (Apache-2.0), independently decodes generated symbols

ZXing Java core 3.5.4 and ZXing-C++ 3.1.1 (Apache-2.0) independently validate
PNG/matrix decoding and control metadata. Their versions and artifact SHA-256
hashes are pinned in Scripts/verify-zxing.mjs and Scripts/zxing-java.

These are downloaded for testing outside Sources and are not Swift Package
runtime dependencies. The test runner compares outputs; it does not vendor
third-party encoder source into the library.

## Toolchain used for this work

Swift 6.4.0 RELEASE, official Debian 13 x86_64 distribution from swift.org.
The download signature verified cryptographically with the official Swift 6.x
signing key. GPG reported that the key expired September 16, after the September
14 signing. No third-party compiler distribution was used. This toolchain and
its download are not included in the release archive.

Minimum-version verification additionally used official Swift6.0.3 Ubuntu24.04
on this Debian13 host; debug/release builds and all tests pass without compiler
warnings. Both original toolchain downloads are excluded from this distribution.

Initial Apple validation used the user's existing Command Line Tools 27.0.0.0.1787197235:
Apple Swift 6.4 (swiftlang-6.4.0.33.1, clang-2100.3.33.1), macOS SDK 27.0
(26A5419a), on arm64 macOS 27.0 (26A428). No Xcode, SDK or toolchain was installed
during that initial phase.
The independent consumer uses the bundled Swift Testing 2078, Core Graphics,
ImageIO and Vision. The original XCTest attempts failed because XCTest was absent.
These historical results remain in `evidence/apple/README.md` and its original logs.

After the user's explicit authorization, official Xcode 27.0 (build 27A266a) was
installed and retained on the same arm64 macOS 27.0 (26A428) host. The subsequent
toolchain was Apple Swift 6.4 (swiftlang-6.4.0.34.1, clang-2100.3.34.1), with
macOS SDK 27.0 (26A425) and bundled Swift Testing 2084. The original package's
debug/release suites each executed 54 XCTest and 2 Swift Testing methods with
no failures, including the conditional Core Graphics/Vision test. The Basic
consumer passed its release build/run, and the independent 10-method consumer
passed again in both configurations. No library source changes were needed.

The Xcode device SDKs were iOS 27.0 (24A430), tvOS 27.0 (24J360), and watchOS
27.0 (24R360). All eight debug/release source-compile lanes passed. Object load
commands verify minimum iOS 16 and tvOS 16 on arm64 and watchOS 9 on arm64_32.
The additional watchOS arm64 lanes emitted minimum watchOS 26 despite the
requested watchOS 9 triple; they do not prove watchOS 9 arm64 compatibility.
These SDK checks do not imply linking, deployment, signing or execution on a
device or simulator.

Separate actual simulator execution used iOS 27.0 (24A434), iPhone 17, arm64.
Debug and release each passed 54 XCTest +2 Swift Testing methods, with zero
failures and zero skips. The only additional test-source change configures
Vision revision 2 and a supported CPU device on the iOS simulator; the default
SpecQR image and exact-payload assertion are unchanged. Revision 2 is deprecated
but remains in this runtime's supported revisions. Native macOS retains the
default request configuration, and production library source is unchanged.

The default revision 4 initially threw Vision Code 9, "Could not create inference
context." An independent 40-request simulator probe compared default/enlarged
SpecQR images against Apple's CoreImage-generated QR control: revisions 3/4
returned no observations for both generators, while revision 1 and revision 2
with CPU recovered the payload. The probe records 19 exact matches, 20 empty
results and one inference error; its diagnostic-process exit 0 is not a claim
that all cases passed. This establishes a current simulator limitation, not a
verified SpecQR renderer defect or successful default-revision validation.
Full evidence is in `evidence/xcode/vision-probe/README.txt`. The test-only branch
does not change the runtime source covered by the earlier Linux reruns.
See `evidence/xcode/README.md` and `evidence/xcode/sdk/README.txt` for the later
evidence and the remaining validation gates.
