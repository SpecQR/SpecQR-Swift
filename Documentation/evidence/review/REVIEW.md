# Independent Swift implementation review

Review date: 2026-10-03. Baseline: SpecQR JavaScript `3.0.0-rc.2`, commit `15ad15e5c770ea0e39072f8f88b2733018f02ffd`.

## Result

No unresolved blocking source defect remains in the reviewed Linux implementation. Review findings were reported to the implementation authors, corrected, and checked in isolated copies of the source. The final source-file hashes are recorded in `reviewed-source-sha256.txt`. Apple runtime and SDK validation is a separate, unexecuted gate in this review.

This is feature compatibility with an explicit correctness correction: high-level GS1/FNC1 input containing a literal percent sign must preserve that character. It is not a claim that every input produces the same matrix as an upstream implementation that can reinterpret the percent sign.

## Findings addressed

1. **GS1/FNC1 literal-percent corruption.** An independent ZXing-C++ decoder confirmed that upstream-compatible alphanumeric `10ABC%DEF` scans as `10ABC` + ASCII GS + `DEF`. The high-level Swift text APIs now choose byte mode when GS1 or FNC1-second is enabled and literal `%` occurs. Explicit alphanumeric requests are rejected with actionable guidance. Manual alphanumeric `%` combined with high-level FNC1 options is also rejected. Explicit manual FNC1 control segments retain low-level QR escaping semantics, including `%%` for one literal percent. `estimate` and generation use the same safeguards. This is a deliberate, documented baseline divergence.
2. **Matrix-free render diagnostics missing.** `QRPlan.renderDiagnostics` now exposes quiet-zone, color, print, and capacity inspection without building a matrix or Reed–Solomon codewords. Overflow plans use the evaluated version; planning omits raster-only warnings. Typed warning details preserve severity and associated measurements.
3. **Large Structured Append performance.** The original implementation repeatedly reconstructed full optimizer histories while testing splits. A 100,000-digit release probe took 37.93 seconds. Safe lower bounds, homogeneous-mode counting, and a seven-state incremental cost tracker reduce repeated work while preserving exact matrices and split metadata. The final equivalent probe took 0.116 seconds; a 37,500-character mixed probe took 0.132 seconds.
4. **Digital Link authority edge cases.** Abbreviated/hex/octal IPv4 and IPv6 canonicalization mismatches were corrected. Oversized ports are rejected before Foundation can represent them as an absent numeric port. Hexadecimal IPv4 components beyond `UInt64` are classified as numeric syntax and rejected rather than silently reinterpreted as a DNS name. The final fixtures include these cases.
5. **Malformed header getters could trap.** Caller-created Structured Append headers containing `Int.min` could underflow public encoded-field getters. `isValid` and optional encoded fields now avoid traps while generation continues to reject invalid headers.
6. **Examples and verification defects.** The README Digital Link example now supplies its required base URL and is covered by executable documentation tests. A GS1 test's ambiguous `.none` spelling was corrected. The differential driver no longer inserts forbidden `data` properties into control segments. Apple-specific image/decoder tests were added, with their unrun status retained.

## Executed independent checks

- Swift 6.4.0 on Linux, isolated final source copy: **59 tests passed in debug and 59 in release**, zero failures. This count comprises **55 package tests plus four reviewer-only tests**. Logs: `final-reviewed-debug.log`, `final-reviewed-release.log`.
- **700 deterministic randomized exact-matrix comparisons** against the pinned JavaScript baseline passed. These vary Unicode payloads, error correction, version bands, ECI, and optimization. This comparison checks complete matrices, not only successful decoding. Driver: `randomized-matrix.mjs`; result: `randomized-matrix-final.log`.
- Package fixtures exercised **1,411 GS1 cases** and **22 Structured Append cases**. Structured Append checks every matrix module and split metadata. The separate GS1 host-overflow reproducer now passes.
- **1,800 additional mixed-Unicode cost-tracker comparisons** against the full optimizer passed across versions 1, 9, 10, 26, 27, and 40. Driver test: `ReviewTrackerTests.swift`; log: `tracker-tests.log`.
- Percent-safety probes cover single/repeated percent signs, GS separators, optimization on/off, high-level/manual options, both FNC1 forms, indicator variants, estimate/generation agreement, unchanged ordinary alphanumeric input, exact capacity, and overflow.
- Resource review checked rendering integer arithmetic and allocation budgets, bounded QR dimensions, preflight rejection, matrix value isolation, immutable shared tables, and Swift `Sendable` result types. Concurrent generation/rendering tests passed.
- Indicative release timings: 100,000 numeric characters → 16 symbols/version 38, 0.116 s; 40,000 lowercase characters → 16/version 37, 0.057 s; 20,000 Kanji characters → 16/version 33, 0.056 s; 37,500 mixed characters → 16/version 36, 0.132 s. These are observations, not performance guarantees. Log: `sa-performance-final.jsonl`.

## Associated final decoder evidence inspected

The final rebuilt CLI identified by SHA-256 `6e3b84a0c0d8f22c45aef857b2125cfa265349a29b976232b338a5eb42ccb5ce` passed both independent decoder lanes. Their executed JSON reports were inspected and copied alongside this review:

- ZXing Java 3.5.4: 419 PNG detections and 419 direct-matrix decodes, 135 Structured Append headers, six high-level sets/48 symbols, 32 controlled three-codeword damage checks, and invalid-symbol rejection. High-level GS1 literal-percent cases pass.
- ZXing-C++ 3.1.1: 608 FNC1-second symbols covering all 152 accepted application indicators, plus 32 high-level GS1/FNC1-second percent-and-separator cases. Literal `%`, repeated `%%`, and actual U+001D are preserved with auto/byte modes and optimization on/off. Explicit low-level alphanumeric escaping remains separately verified.

The Java decoder cannot consume the FNC1-second application indicator correctly; no Java verification claim is made for that mode. The C++ lane supplies that coverage. These checks are synthetic decodes, not camera or print certification.

## Limits and release gates

- This review did **not** execute Core Graphics or Vision on Apple hardware, or build against iOS/tvOS/watchOS SDKs. The adapter's source is plausible and conditional tests are present; that does not constitute an Apple pass.
- Minimum Swift 6.0 validation and final integrated decoder runs are maintained in the release's overall verification record; this report's own compiler was Swift 6.4.0.
- Low-level explicit FNC1 segments intentionally require QR alphanumeric escaping knowledge. GS1 helper support is the documented 50-AI catalog, not full GS1 certification or calendar validation.
- Physical printing, damaged-symbol tolerance, camera behavior, and every scanner's metadata API require separate environment/device testing.
- Final distribution assembly and archive checksums must correspond to the verified source; this review does not assert an archive hash.
- No repository creation, push, pull request, tag, release, or package publication was performed during this review.
