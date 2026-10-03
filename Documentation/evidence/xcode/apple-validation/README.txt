Independent Apple consumer rerun with full Xcode — 2026-10-03

PASS: debug and release each executed all 10 Swift Testing test methods in
2 suites, with no failures or skips. This is genuine native arm64 macOS
execution of the existing public-API consumer, separate from root XCTest.

Environment:
- Xcode 27.0, build 27A266a
- Apple Swift 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
- Host macOS 27.0, build 26A428, arm64
- DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer (process scope only)

Per-configuration coverage:
- Core Graphics: exact straight RGBA bytes, alpha/channel metadata, no
  interpolation, and retained backing storage after the producer is destroyed.
- ImageIO: 4 PNG decode-to-every-original-pixel roundtrips.
- Vision: 17 actual decodes with payload assertions: 5 ordinary/Unicode inputs
  through CGImage and PNG (10); 3 GS1 percent/repeated-percent/separator inputs
  through both routes (6); one low-level escaped alphanumeric GS1 input (1).
  The first 16 compare UTF-8 bytes exactly, including decomposed Unicode,
  emoji, Japanese text and U+001D. The low-level ASCII test compares the exact
  expected string. These assertions validate decoded contents, not generation
  alone; successful image creation never substitutes for decoder agreement.
- Both FNC1 forms retain the safe percent behavior in planning/generation,
  auto/explicit-byte modes, optimization on/off and unsafe-alpha rejection.
- All 1,411 GS1 fixtures and 22 Structured Append fixtures.
- Structured Append headers, payload ranges, shuffled merge and bad/missing/
  duplicated/corrupt-part rejection; render limits and 32 concurrent renders.

Case counts above are assertions inside the 10 test methods, not extra tests.
No source, test or wrapper changed. The wrapper's existing `xcode-select -p`
already honors DEVELOPER_DIR: bash trace resolves it to Xcode and resolves
swiftc/Testing plugins inside that same Xcode installation. Thus the suggested
fallback expression change was unnecessary. Global xcode-select remained CLT.

Evidence:
- debug.log / release.log: full bash command/argument traces, build and test logs
- environment.log: native version commands and toolchain resolution
- input-sha256.json: all library/test/wrapper input hashes
- results.json: commands, exit codes, durations, 60 generated artifact hashes,
  unchanged-input confirmation and cleanup status
- artifacts.log: retained file-type/architecture inspection before cleanup
- run-apple-validation.py: reproducible runner for both configurations

Reproduce from the package root:
  python3 Documentation/evidence/xcode/apple-validation/run-apple-validation.py

Only owned .build-xcode-apple-validation and
.build-xcode-apple-validation-support directories were removed after evidence
capture. Earlier CLT evidence remains intact. About 15 GiB free at completion.

No simulator/device execution, minimum-OS runtime, physical-camera/print,
scanner certification or remote publication is established by this lane.
