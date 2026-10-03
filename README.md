# SpecQR for Swift

A dependency-free Swift QR Code Model 2 encoder, independently authored for
feature compatibility with SpecQR JavaScript 3.0.0-rc.2.

SpecQR の Swift 実装です。QR ライブラリ、OS の QR 生成器、JavaScript ランタイムを
実行時に使用しません。Swift 標準ライブラリと Foundation だけで生成します。

公開ソース repository は [SpecQR/SpecQR-Swift](https://github.com/SpecQR/SpecQR-Swift) です。
初回のソース公開段階で、`main` branch を利用できます。安定版の version tag と
GitHub Release はまだありません。実行済みの検証と制限は
[検証結果](Documentation/VERIFICATION.md)、公開 commit の CI 状態は
[GitHub Actions](https://github.com/SpecQR/SpecQR-Swift/actions)を参照してください。

## Swift Package

Swift 6.0 以降。Linux と Apple プラットフォームを対象にしています。
macOS 13、iOS/tvOS 16、watchOS 9 を deployment minimum として宣言しています。
Apple 向けの動作確認状況は検証結果と区別して扱ってください。

`Package.swift` の dependencies に `main` branch を追加できます。

```swift
.package(url: "https://github.com/SpecQR/SpecQR-Swift.git", branch: "main")
// target dependencies: [.product(name: "SpecQR", package: "SpecQR-Swift")]
```

ローカル checkout を package として追加する場合:

```swift
.package(path: "../SpecQR-Swift")
// target dependencies: [.product(name: "SpecQR", package: "SpecQR-Swift")]
```

```swift
import Foundation
import SpecQR

let code = try SpecQR.generate("https://example.com", options: .init(errorCorrectionLevel: .Q))
let matrix = code.matrix                 // [[Bool]], quiet zone を含まない
let svg = try code.svg()                 // margin 4, scale 8
let png = try code.png()                 // Foundation.Data
try png.write(to: URL(fileURLWithPath: "qr.png"))
```

## 対応範囲

- QR Code Model 2、Version 1–40、ECC L/M/Q/H、mask 0–7 と自動選択
- Numeric / Alphanumeric / UTF-8 Byte / Kanji、binary、manual/mixed segments
- 自動 mode 最適化、Version 範囲、同一 Version 内の ECC boost
- ECI、FNC1 first/second、低レベル Structured Append control
- matrix を構築しない planning、capacity、overflow diagnostics
- GS1 の代表 50 AI、element string、check digit、GS1 Digital Link
- 高レベル Structured Append の分割、parity、再結合、summary/full diagnostics
- SVG / PNG / data URL / RGBA、portable canvas、条件付き Core Graphics adapter

Micro QR、rMQR、Hanzi mode、任意の文字コード変換、QR の読み取り機能は対象外です。
ECI は文字コードラベルで、文字列の符号化自体は UTF-8 です。
Kanji 対応表は固定され、OS の locale やエンコーダーに依存しません。

## Planning と明示的な segments

```swift
let plan = try SpecQR.estimate("HELLO", options: .init(maxVersion: 5))
if plan.ok {
    print(plan.selectedVersion!, plan.remainingBits)
} else {
    print(plan.overflowBits)
}
let capacity = try SpecQR.getCapacity(version: 1, errorCorrectionLevel: .M, mode: .byte)
let code = try SpecQR.generate(segments: [
    .eci(26), .alphanumeric("ORDER "), .numeric("1234567890"), .byte("-こんにちは")
])
```

`estimate` / `analyzeSegments` は容量不足を `ok == false` として返します。
不正な入力や options は throw します。`generate` は容量不足も throw します。
`Data` / `[UInt8]` を使うと binary payload の値をそのまま維持できます。

## GS1

```swift
let elements = try GS1.parseHumanReadable("(01)09501101530003(10)LOT123(17)271231")
let raw = try GS1.createElementString(elements)
let code = try SpecQR.generate(raw, options: .init(gs1: true))
let link = try GS1.createDigitalLink(elements, options: .init(baseURL: "https://example.com"))
let validation = GS1.validateElements(elements)
```

対応 AI は `GS1.getSupportedAIs()` / `GS1.getAIInfo(_:)` で確認できます。
重要: raw GS1 / FNC1-second の文字列に literal `%` が含まれる場合、auto mode は
byte mode を選び、元の文字を保持します。明示的 alphanumeric mode は安全のため
拒否します。これは pinned JavaScript の文字化けを修正する、限定的な互換差分です。
低レベルの FNC1 segments では標準の `%` / `%%` escape semantics が適用されます。
詳細は [互換性と安全性](Documentation/COMPATIBILITY.md)を参照してください。

全 GS1 規格の適合を認証する API ではありません。日付は upstream と同じく
文字種・桁数を検証し、暦としての有効性までは検証しません。

## Structured Append

```swift
let set = try SpecQR.generateStructuredAppend(String(repeating: "abc", count: 40),
    options: .init(qrOptions: .init(version: 1), maxSymbols: 16))
for (index, symbol) in set.symbols.enumerated() {
    try symbol.png().write(to: URL(fileURLWithPath: "part-\(index + 1).png"))
}
```

index は 1 始まり、2–16 symbols です。高レベル API は headers と parity を管理し、
ECI、GS1/FNC1、ECC boost の組み合わせを拒否します。scanner が Structured Append
metadata を露出するとは限りません。正確な再結合には metadata が必要です。
XOR parity は誤り検出の補助であり、暗号学的な整合性保証ではありません。

## 描画と scan diagnostics

```swift
let render = QRRenderOptions(margin: 4, scale: 8, foreground: "#000", background: "#fff", printDPI: 300)
let warnings = try code.renderDiagnostics(options: render).warnings
let url = try code.pngDataURL(options: render)
#if canImport(CoreGraphics)
let image = try code.cgImage(options: render)
#endif
```

Raster は 4,194,304 pixels、SVG は 8 MiB の上限を設け、整数 overflow 前に失敗します。
PNG は #RGB/#RGBA/#RRGGBB/#RRGGBBAA と black/white/transparent に対応します。
SVG は属性値をエスケープします。安全性や読み取りやすさには白地・黒を推奨します。

## CLI と検証

```sh
swift run specqr-cli 'HELLO WORLD' > qr.svg
swift run specqr-cli --png qr.png 'HELLO WORLD'
echo '{"text":"HELLO","options":{"errorCorrectionLevel":"Q"}}' | swift run specqr-cli --json-lines
swift test
swift test -c release
./Scripts/verify-all.sh
```

通常の Swift tests はネットワーク不要です。全外部検証には Node 20+、Java 17+、
Python 3.10+ と pip、curl が必要です。`verify-all.sh` は検証用として pinned
upstream と npm の decoder/reference を取得します。これらは Swift product に
リンク・同梱されません。詳細は [API](Documentation/API.md)、
[parity](Documentation/PARITY.md)、[provenance](Documentation/PROVENANCE.md) を参照してください。

Linux/macOS の実行検証、iOS/tvOS/watchOS の SDK compile、iOS 27.0 simulator の
debug/release tests を実施しています。iOS simulator の Vision test は revision 2 と対応 CPU を
明示しています。この runtime の default revision 4 は inference error、revision 3/4 は
SpecQR と Apple CoreImage の対照 QR の両方で decode 不成立でした。default revision の
成功や physical camera・印刷物・最低 deployment OS での実行を示す結果ではありません。
詳細は [検証結果](Documentation/VERIFICATION.md)を参照してください。
