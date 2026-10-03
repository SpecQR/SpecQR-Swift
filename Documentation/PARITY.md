# Feature parity acceptance checklist

Baseline: SpecQR JavaScript `3.0.0-rc.2`, exact commit
`15ad15e5c770ea0e39072f8f88b2733018f02ffd` (2026-08-02).
Canonical source: https://github.com/SpecQR/SpecQR/tree/15ad15e5c770ea0e39072f8f88b2733018f02ffd

The high-level literal-percent correctness divergence is documented in COMPATIBILITY.md.
This Swift implementation is newly authored. Previously produced Swift archives
could not be materialized in this environment and were not used as source.
The checklist records acceptance criteria; checked status requires executed evidence.

- [x] Swift Package builds in debug and release with zero package/runtime dependencies
- [x] Model 2 versions 1–40, levels L/M/Q/H, masks 0–7 and automatic minimum-penalty selection
- [x] Numeric, alphanumeric, UTF-8 byte, raw binary, deterministic Kanji and mixed/manual segments
- [x] Auto segmentation, count-field boundaries, exact version/range options, ECC boost
- [x] ECI, FNC1 first/second, Structured Append low-level controls and ordering/conflict validation
- [x] Planning without matrix construction, estimates including overflow, capacity queries
- [x] Generation diagnostics, capacity, segments, mask scores, render/scan warnings
- [x] GS1 AI dictionary, human-readable/raw parsers, validators and GTIN/SSCC check digits
- [x] GS1 Digital Link create/parse/validate/normalize
- [x] Structured Append text/binary/manual splitting, canonical parity, merge validation, diagnostics
- [x] Matrix, SVG, PNG, data URLs, portable RGBA; overflow-safe rendering budgets
- [x] Swift platform adapters and conditional tests prepared; unrun status disclosed
- [ ] Apple SDK/platform execution gate (requires Apple environment)
- [x] Actual source-backed differential fixtures across modes, versions, ECC and masks
- [x] Independent QR decoder/reference validation
- [x] Negative cases, boundaries, large input, concurrency and immutable result safety
- [x] CLI, examples, API documentation, licensing/provenance and unpublished release checklist
- [x] Independent integrated code review addressed; distribution checksums provided alongside archive
- [x] No repository creation, push, PR, tag, release or package publication
