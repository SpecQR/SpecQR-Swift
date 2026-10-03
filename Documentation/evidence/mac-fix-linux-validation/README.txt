Mac-discovered fixes: Linux regression evidence, 2026-10-03

Exactly two changes:
1. Examples/Basic/Package.swift declares macOS13, matching its dependency.
2. Rendering.swift compares Int64(dimension) with the 53-bit-safe upper bound,
   avoiding an out-of-range Int literal on arm64_32 while preserving 64-bit behavior.

Swift6.0.3: debug/release builds and each53 XCTest+2 SwiftTesting pass, zero compiler warnings.
Swift6.4: debug/release tests plus complete external aggregate pass.
Both compiler versions also build/run the isolated Basic consumer on Linux.
All ordinary rendering/resource-overflow tests pass. Fixed-case oracle/render outputs are unchanged.

External corpora:1280fixedQR,136auto/control,288planning,15invalid,11render,
16intentionalFNC1safetychecks,960Nayuki,12jsQR,419ZXingPNG+419matrix,
135SAheaders,48high-levelSA symbols,32damage recoveries,
608FNC1-second symbols,32percent/separator regressions. Suite counts overlap.

This evidence is Linux-only. It does not claim macOS XCTest, Apple SDK builds,
Vision, iOS/tvOS/watchOS, or watchOS arm64_32 execution. Those remain separately gated.
No existing Library artifact was replaced. No GitHub publication or remote write occurred.

patch.diff is the exact narrow diff. patched-files/ contains both final files.
changed-source-sha256.txt and source manifests identify tested inputs.
The final Swift6.4 aggregate reports identify its actual CLI binary hash.
