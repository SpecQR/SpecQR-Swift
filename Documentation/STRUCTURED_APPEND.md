# Structured Append

一つの入力を 2–16 symbols に分割し、canonical parity と scanner metadata で再結合します。
text は Unicode scalar 境界、binary は byte 境界を保持します。manual の numeric /
alphanumeric / Kanji segments は分割せず、byte segments だけを分割します。
概要は README、以下は public API と厳密な分割規則の参照です。

The high-level Structured Append API partitions one payload into **2–16 QR Model 2 symbols** with a shared version, error correction level, and parity. Its split decisions, canonical bytes, matrices, and diagnostics follow SpecQR JavaScript **3.0.0-rc.2**, commit `15ad15e5c770ea0e39072f8f88b2733018f02ffd`.

## Generate a text or binary set

```swift
import SpecQR

let set = try SpecQR.generateStructuredAppend(
   String(repeating: "A", count: 31),
   options: QRStructuredAppendOptions(
      qrOptions: QROptions(
         errorCorrectionLevel: .L,
         version: 1,
         maskPattern: 0,
         mode: .alphanumeric
      ),
      maxSymbols: 16
   )
)

assert(set.total == 2)
assert(set.diagnostics.symbols.map(\.inputLength) == [21, 10])
let firstSymbol: QRCode = set.symbols[0]
```

`generateStructuredAppend` also accepts `[UInt8]` and Foundation `Data`, including slices with nonzero starting indices. Binary input requires `.auto` or `.byte` mode. Text is UTF-8 when encoded in byte mode.

With an explicit version, every symbol uses that version. With `version: nil`, the algorithm tries `minVersion...maxVersion` in ascending order and chooses the **smallest version that produces a valid set** within `maxSymbols`. It does not minimize the number of symbols or balance their lengths. Each part receives the largest fitting prefix, accounting for the 20-bit Structured Append header.

The high-level API rejects input that fits in one header-bearing symbol in the selected range. Use normal `generate` for a single symbol, or supply `QROptions.structuredAppend` when externally managing a set.

Text splits occur at **Unicode scalar boundaries**, matching JavaScript code-point iteration. An emoji scalar is never divided into partial UTF-8 bytes. Combining sequences and multi-scalar grapheme clusters may cross part boundaries. `inputStart` and `inputLength` count scalars; `byteStart` and `byteLength` count canonical UTF-8 bytes. All offsets are zero-based.

## Preserve manual segment boundaries

```swift
let segments: [QRSegment] = [
   .alphanumeric("ABCDEFGHIJKLMNOPQRSTU"),
   .numeric("12345678901234567890"),
   .byte([0, 1, 2, 255])
]
let set = try SpecQR.generateSegmentsStructuredAppend(
   segments,
   options: .init(
      qrOptions: .init(errorCorrectionLevel: .L, version: 1, maskPattern: 0),
      diagnostics: true,
      splitUnits: .full
   )
)
```

Manual splitting preserves caller segmentation:

- Numeric, alphanumeric, and Kanji segments are indivisible, even if splitting one would otherwise allow the payload to fit.
- Binary `.byte([UInt8])` segments split per byte.
- `.byteText(String)`, also constructed using `.byte(String)`, splits per Unicode scalar.
- Adjacent segments remain separate. Their individual mode/count overhead is retained.
- Empty segments and all control segments are rejected.

For manual input, `inputLength` and `segmentCount` are the source segment count. `sourceSegmentStart..<sourceSegmentEnd` identifies source segments contributing to one output symbol; the end is exclusive. `splitUnitStart` and `splitUnitLength` identify the range in the logical split-unit sequence.

## Parity and merging

```swift
let parity = SpecQR.calculateStructuredAppendParity("AB")
let parts = [
   QRStructuredAppendPart(index: 2, total: 2, parity: parity, text: "B"),
   QRStructuredAppendPart(index: 1, total: 2, parity: parity, text: "A")
]
let merged = try SpecQR.mergeStructuredAppendParts(parts)
assert(merged.data == .text("AB"))
```

`calculateStructuredAppendParity` accepts `String`, `[UInt8]`, and `Data`. Empty input has parity zero. `calculateStructuredAppendSegmentsParity` accepts validated nonempty manual data segments.

Parity is XOR over the **original canonical bytes**. Numeric/alphanumeric text contributes ASCII bytes; byte text and Kanji contribute UTF-8 bytes; binary contributes its raw bytes. Kanji parity deliberately uses UTF-8 even though QR Kanji-mode encoding uses the Shift-JIS-derived 13-bit representation.

`mergeStructuredAppendParts` accepts already decoded parts, sorts by one-based index, and verifies:

1. Index range 1–16, total range 2–16, and index not greater than total
2. Consistent total and parity across every part
3. One consistent text or binary payload kind
4. Every expected index exactly once
5. Matching XOR parity after canonical concatenation

Successful merges return `.text(String)` or `.bytes([UInt8])`, sorted metadata, and parity-check diagnostics. Consistent empty decoded chunks are permitted, matching the JavaScript utility. The helper does not scan or decode QR images. XOR parity is not cryptographic integrity or authentication and cannot detect every possible corruption.

## Diagnostics and Swift adaptations

Results, parts, options, warnings, and diagnostic records are immutable `Sendable` value types. Every symbol is a normal `QRCode`, so its full core diagnostics are always accessible. Swift does not reproduce JavaScript's output-dependent union of matrices, rendered outputs, and diagnostic wrappers. Render each `QRCode` using the normal rendering API.

`QRStructuredAppendOptions` contains:

- `qrOptions: QROptions`, defaulting to normal core options
- `maxSymbols: Int`, default 16, valid range 2–16
- `diagnostics: Bool`, default false; enables the decoder-compatibility warning
- `splitUnits: QRStructuredAppendSplitUnitsDetail`, default `.summary`

Every result includes summary diagnostics and per-symbol ranges/bit accounting regardless of `diagnostics`. Manual `.summary` includes the split-unit count but leaves `splitUnits` nil. Manual `.full` expands every split unit into metadata. Full detail on text/binary high-level generation is rejected because that contract applies to manual segments.

The result warns when it uses exactly `maxSymbols`. Decoder metadata support varies, so `diagnostics: true` also emits `STRUCTURED_APPEND_DECODER_SUPPORT_VARIES`.

The high-level API rejects ECI, GS1/FNC1, user-supplied Structured Append headers, and error-correction boosting. Manual generation additionally requires `qrOptions.mode == .auto` and `optimizeSegments == true`; these normalized defaults preserve supplied segments and do not run text optimization on them. Swift value types do not track whether a caller explicitly wrote a default-valued option, unlike JavaScript's property-presence validation. Unsupported JavaScript aliases, parity overrides, and arbitrary option keys have no typed Swift equivalents. `UInt8` makes invalid byte/parity ranges unrepresentable.

Split capacity failures use `QRError.structuredAppendTooLong` with code `DATA_TOO_LONG` and a message explaining the selected versions, error correction, and symbol limit. This separate case avoids misleading per-symbol bit counts when the actual constraint is an indivisible manual segment or the set's symbol limit.

## Resource behavior

Capacity lower bounds reject obviously oversized input before text indexing or split-unit expansion. Text indexing stores Unicode scalars and canonical byte offsets, using O(n) memory. This is a Swift representation choice rather than a copy of the JavaScript sparse UTF-16 index.

Pure numeric, nondigit alphanumeric, Kanji, and byte-only inputs use exact direct bit counting where a single mode is provably optimal. Mixed automatic text splitting uses a seven-state incremental cost tracker. It retains only current bit costs and stops at the first nonfitting prefix; it does not repeatedly construct full optimizer histories. Final symbols use the normal core optimizer for segment reconstruction and tie-breaking.

Manual descriptors retain source segment boundaries. Full per-byte/per-scalar split-unit records are created only for `.full` diagnostics. Normal results hold at most 16 symbol matrices, with normal QR version limits. There is no arbitrary payload-size cutoff separate from QR capacity limits. No JavaScript, Node, network service, or third-party QR encoder is used at runtime.

## Verification and fixture regeneration

`StructuredAppendTests` covers 22 pinned JavaScript differential cases, checking **every matrix module** and the split metadata. Cases include all four ECC levels, fixed/automatic versions, count-width bands at versions 10 and 27, Unicode scalars, optimized/unoptimized automatic modes, manual atomic segments, binary chunks, and a full 16-part set.

Additional tests cover parity, corrupted and incomplete merges, unsupported options, empty/single inputs, indivisible-segment overflow, large-input preflight, data slices, value isolation, error messages, and incremental-tracker agreement with the core across 2,720 deterministic randomized prefixes.

Fixture regeneration is developer-only and requires Node plus a clean checkout of the pinned upstream commit:

```sh
node Scripts/generate-structured-append-fixtures.mjs /path/to/SpecQR-JS
swift test --filter StructuredAppendTests
```

The generator verifies the upstream package version, commit, and tracked source/fixture cleanliness before writing the fixture file. Tests and the Swift package require no Node installation.
