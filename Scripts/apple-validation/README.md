# Independent macOS consumer validation

This Swift Testing package depends on the root `SpecQR` library by a local path
and uses public APIs only. It imports Core Graphics, ImageIO and Vision
unconditionally; a missing framework fails the build instead of producing a
skipped test reported as a pass. It installs no external dependencies.

From the repository root:

```sh
./Scripts/verify-apple.sh
# Or one configuration:
./Scripts/verify-apple.sh release
```

The consumer tests exercise straight RGBA provider bytes, Core Graphics image
metadata and storage lifetime, actual PNG decoding through ImageIO, Vision
decoding from both CGImage and PNG, UTF-8 and GS1 literal percent/group separator
preservation, invalid rendering and resource limits, both FNC1 forms, Structured
Append headers/shuffled merging/parity rejection, and concurrent rendering.
Two corpus tests replay all 1,411 GS1 and 22 Structured Append fixtures directly
from the original root test resources.

The script supplies installed Testing macro and runtime paths that some CLT
releases omit, uses two build jobs, and keeps caches under `.build`. Optional
`SPECQR_APPLE_BUILD_DIR` and `SPECQR_APPLE_CACHE_DIR` set absolute storage paths.
The independent test runner targets macOS 14 because the installed Testing
framework requires it; the library and Basic consumer still target macOS 13.

This is additional macOS evidence. It does not execute or replace the original
XCTest test suite. Apple's Command Line Tools can lack XCTest even when the
compiler, macOS SDK, and Swift Testing are available. Record the original suite
as blocked when that happens; this package is an independent consumer lane.

No result from this package proves iOS/tvOS/watchOS SDK or simulator execution,
deployment-minimum runtime behavior, physical-camera scanning, print quality,
or barcode-standard certification. Vision expectations are explicit failures
if the local decoder cannot preserve a tested payload; investigate and record
that limitation rather than silently omitting the assertion.
