# Swift API と JavaScript API の対応

## 設計

Swift では不正な値の組み合わせをできるだけ型で防ぎます。`SpecQR` は namespace、
`QRCode` は変更不能な生成結果です。JavaScript の `QRCode.generate` と top-level
functions は Swift の `SpecQR.generate` に対応します。

JavaScript の output 指定によって型が変わる戻り値は採用しません。まず `QRCode` を
作り、その `.matrix` / `.svg()` / `.png()` / data URL methods を使用します。
全 public result/options は `Sendable` な value types です。Foundation `Data` も使えます。

## Encoder

| Swift | 対応機能 |
|---|---|
| `SpecQR.generate(String, options:)` | UTF-8 text / auto mode |
| `SpecQR.generate([UInt8], options:)` / `generate(Data, options:)` | raw binary byte mode |
| `SpecQR.generate(segments:options:)` / `generateSegments(_:options:)` | manual mixed/control segments |
| `SpecQR.estimate(_:options:)` | matrix/RS を構築しない planning |
| `SpecQR.analyzeSegments(_:options:)` | manual planning |
| `SpecQR.getCapacity(version:errorCorrectionLevel:mode:controlBits:)` | capacity query |

`QROptions` の default: M、auto version (1...40)、auto mask、auto mode、
optimizeSegments true、boostErrorCorrection false、ECI/GS1/FNC1/SA disabled。
`eci: 26` は JavaScript の `eci: true` と同義です。任意 ECI assignment はラベルだけで、
UTF-8 以外への text transcoding は行いません。

`QRSegment`: `.numeric(String)`、`.alphanumeric(String)`、`.kanji(String)`、
`.byte([UInt8])`、`.byte(String)` / `.byteText(String)`、`.eci(Int)`、`.fnc1`、
`.fnc1Second(String)`、`.structuredAppend(index:total:parity:)`。

[FNC1 literal-percent の安全上の差分](COMPATIBILITY.md)を除き、
Version/ECC/mask/tie-break decisions、data codewords、interleaved codewords、matrices、
segments と bit counts は pinned upstream と差分検証しています。文字数は Unicode
scalar 数であり、Swift の grapheme cluster count と異なります。Kanji segment の
byteCount は QR の Shift_JIS bytes、Structured Append parity の Kanji は UTF-8 bytes です。

## Planning と diagnostics

`QRPlan.ok == false` は容量不足です。固定 Version は selectedVersion を保持し、
auto-range が尽きた場合は nil。両方とも evaluatedVersion で報告容量の Version を確認できます。
`generate` は容量不足を throw します。不正な options/input は planning でも throw します。

`QRCode.diagnostics` は mask scores、data/ECC/total codeword count と planning を保持します。
`QRCode.dataCodewords` / `.codewords` はテスト・解析に使える値コピーです。

描画設定は `QRRenderOptions` に分離しています。
`QRPlan.renderDiagnostics(options:)` は matrix を作らずに quiet zone、contrast、印刷寸法、
容量の警告を返します。overflow 時も使用でき、その寸法は evaluatedVersion を用います。
`QRCode.renderDiagnostics(options:raster:)` は描画段階の診断です。raster default は true。
SVG だけの診断には `raster: false` を指定します。

`QRRenderDiagnostics.warnings` は code の一覧、`.warningDetails` は同じ順序の
`QRWarning` (code / severity / message / typed details) です。alpha は 0...255。
contrast thresholds 4.5/7、quiet zone 4 modules、print minimum 0.25 mm、
raster recommendation 3 pixels/module は upstream と同じです。

## Renderers

- `.svg(options:) -> String`
- `.svgDataURL(options:) -> String`
- `.png(options:) -> Data`
- `.pngDataURL(options:) -> String`
- `.rgba(options:) -> QRRGBAImage` (straight RGBA8)
- `.draw(to: &canvas, options:)` (`QRCanvas` protocol)
- `.cgImage(options:)` (`canImport(CoreGraphics)` の環境のみ)

margin は matrix の外側に追加されます。matrix の内容・寸法自体は不変です。
整数 overflow と resource budgets は allocation 前に検証します。PNG は stored DEFLATE
の deterministic RGBA8 stream。SVG は caller の色値を XML attribute escape します。

## GS1

[GS1 API](GS1.md) を参照してください。helper 名は Swift の略語慣習に合わせた
GTIN / SSCC / AI / URL 表記です。GS1Error は code `INVALID_GS1`。
非throwing validators は typed errors/warnings を返します。

## Structured Append

[Structured Append API](STRUCTURED_APPEND.md) を参照してください。
分割 API の結果は常に `[QRCode]`、compact/full の差は diagnostics の split units に限定。
JavaScript の per-symbol output polymorphism は描画 methods で置き換えています。

## Errors と未対応範囲

`QRError` の code: INVALID_INPUT、INVALID_VERSION、INVALID_MODE、INVALID_ECI、
INVALID_GS1、DATA_TOO_LONG。描画は `QRRenderError`、GS1 helpers は `GS1Error`。
Swift の型で表せない JS wrong-type inputs はコンパイル時または CLI JSON decode 時に拒否します。

Canvas DOM / Node Buffer / Blob の環境固有 wrappers は portable canvas / Data / Core Graphics
に置き換えます。decoder/camera、Micro QR、rMQR、Hanzi、装飾/logo、完全な GS1 catalog
は追加しません。公開先 URL はまだ確定しておらず、この package は未公開です。
