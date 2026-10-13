# Structured Append

一つの入力を 2–16 symbols に分割し、canonical parity と scanner metadata で再結合します。
text は Unicode scalar 境界、binary は byte 境界を保持します。manual の numeric /
alphanumeric / Kanji segments は分割せず、byte segments だけを分割します。
概要は README、以下は public API と厳密な分割規則の参照です。

高レベル Structured Append API は、一つの payload を、version、error correction level、parity を共有する **2–16 個の QR Code Model 2 symbol** に分割します。分割の判断、canonical bytes、matrix、diagnostics は、SpecQR JavaScript **3.0.0-rc.2**、commit `15ad15e5c770ea0e39072f8f88b2733018f02ffd` に従います。

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

`generateStructuredAppend` は、開始 index がゼロでない slice を含め、`[UInt8]` と Foundation `Data` も受け入れます。binary 入力には `.auto` または `.byte` mode が必要です。text を byte mode で符号化するときは UTF-8 を使います。

version を明示すると、すべての symbol がその version を使います。`version: nil` の場合、`minVersion...maxVersion` を昇順に試し、`maxSymbols` 以内で**有効な集合を生成できる最小の version** を選びます。symbol 数の最小化や、各 symbol の長さの均等化は行いません。各 part には、20-bit Structured Append header を考慮し、収容できる最長の prefix を割り当てます。

高レベル API は、選択した範囲内で header 付きの一つの symbol に収まる入力を拒否します。単一 symbol には通常の `generate` を使い、集合を外部で管理する場合は `QROptions.structuredAppend` を指定してください。

text は、JavaScript の code point 単位の反復と同じ **Unicode scalar 境界**で分割します。絵文字の scalar を UTF-8 byte の途中で分割することはありません。結合文字列や複数の scalar からなる grapheme cluster は、part の境界をまたぐ場合があります。`inputStart` と `inputLength` は scalar 数、`byteStart` と `byteLength` は canonical UTF-8 byte 数を数えます。すべての offset はゼロ始まりです。

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

manual 分割は、caller が指定した segment の区切りを維持します。

- numeric、alphanumeric、Kanji segment は、分割すれば payload が収まる場合でも分割しません。
- binary の `.byte([UInt8])` segment は byte 単位で分割します。
- `.byteText(String)` は Unicode scalar 単位で分割します。この segment は `.byte(String)` でも構築できます。
- 隣接する segment は別々のまま維持し、それぞれの mode/count overhead を保持します。
- 空の segment と、すべての control segment を拒否します。

manual 入力の `inputLength` と `segmentCount` は、元の segment 数です。`sourceSegmentStart..<sourceSegmentEnd` は、一つの出力 symbol に寄与する元の segment の範囲を示し、終端は含みません。`splitUnitStart` と `splitUnitLength` は、論理的な split-unit 列内の範囲を示します。

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

`calculateStructuredAppendParity` は `String`、`[UInt8]`、`Data` を受け入れます。空の入力の parity はゼロです。`calculateStructuredAppendSegmentsParity` は、検証済みで空でない manual data segment を受け入れます。

parity は、**元の canonical bytes** 全体の XOR です。numeric/alphanumeric text には ASCII bytes、byte text と Kanji には UTF-8 bytes、binary にはその raw bytes を使います。QR の Kanji mode は Shift-JIS 由来の 13-bit 表現で符号化しますが、Kanji の parity には意図的に UTF-8 を使います。

`mergeStructuredAppendParts` は decode 済みの part を受け取り、1 始まりの index 順に並べ、次の項目を検証します。

1. index は 1–16、total は 2–16 の範囲であり、index が total を超えないこと。
2. すべての part で total と parity が一致すること。
3. payload の種類が text または binary のどちらかに揃っていること。
4. 期待するすべての index が、それぞれ正確に一度だけ現れること。
5. canonical な連結後の XOR parity が一致すること。

再結合に成功すると、`.text(String)` または `.bytes([UInt8])`、整列した metadata、parity 検証の diagnostics を返します。整合する空の decode 済み chunk は、JavaScript utility と同じく許可します。この helper は QR 画像の scan や decode を行いません。XOR parity は暗号学的な整合性保証や認証ではなく、考えられるすべての破損を検出できるわけではありません。

## Diagnostics and Swift adaptations

result、part、option、warning、diagnostic record は、変更不能な `Sendable` の value types です。各 symbol は通常の `QRCode` なので、core diagnostics 全体を常に参照できます。Swift では、output に応じて matrix、描画結果、diagnostic wrapper が切り替わる JavaScript の union を再現しません。各 `QRCode` は通常の描画 API で描画してください。

`QRStructuredAppendOptions` には、次の項目があります。

- `qrOptions: QROptions`: 既定値は通常の core options です。
- `maxSymbols: Int`: 既定値は 16、有効範囲は 2–16 です。
- `diagnostics: Bool`: 既定値は false。decoder 互換性の警告を有効にします。
- `splitUnits: QRStructuredAppendSplitUnitsDetail`: 既定値は `.summary` です。

すべての結果は、`diagnostics` にかかわらず summary diagnostics と symbol ごとの範囲・bit の計算結果を含みます。manual の `.summary` は split-unit 数を含みますが、`splitUnits` は nil のままです。manual の `.full` は、すべての split unit を metadata に展開します。この contract は manual segment に適用するため、高レベルの text/binary 生成に対する full detail の指定は拒否します。

使用数がちょうど `maxSymbols` に達すると、結果に警告が含まれます。decoder の metadata 対応状況には違いがあるため、`diagnostics: true` では `STRUCTURED_APPEND_DECODER_SUPPORT_VARIES` も出力します。

高レベル API は、ECI、GS1/FNC1、利用者が指定した Structured Append header、error-correction boosting を拒否します。manual 生成では、さらに `qrOptions.mode == .auto` と `optimizeSegments == true` が必要です。これらの正規化済みの既定値は、渡された segment を保持し、その segment に text 最適化を実行しません。Swift の value types は、JavaScript の property 存在検証と異なり、caller が既定値と同じ option を明示したかどうかを追跡しません。未対応の JavaScript alias、parity の上書き、任意の option key に相当する Swift の型付き表現はありません。`UInt8` により、不正な byte/parity の範囲は表現できません。

分割時の容量不足には `QRError.structuredAppendTooLong` を使用し、code は `DATA_TOO_LONG`、message は選択した version、error correction、symbol 上限を説明します。この専用 case により、実際の制約が分割不能な manual segment や集合の symbol 上限である場合に、誤解を招く symbol ごとの bit 数を示すことを避けます。

## Resource behavior

容量の lower bound により、text の index 作成や split-unit の展開より前に、明らかに大きすぎる入力を拒否します。text の index は Unicode scalar と canonical byte offset を保存し、O(n) の memory を使用します。これは Swift で選択した表現であり、JavaScript の sparse UTF-16 index をコピーしたものではありません。

数字のみ、数字以外の alphanumeric、Kanji、byte のみの入力では、単一 mode が最適だと証明できる場合に、直接かつ正確に bit 数を数えます。混在した text の自動分割には、七つの状態を持つ incremental cost tracker を使用します。現在の bit cost だけを保持し、最初に収まらなくなった prefix で停止します。optimizer の履歴全体を繰り返し構築することはありません。最終 symbol では、通常の core optimizer を使って segment の復元と tie-break を行います。

manual descriptor は、元の segment の境界を保持します。byte/scalar ごとの完全な split-unit record を作るのは、`.full` diagnostics の場合だけです。通常の結果は、通常の QR version 上限の下で、最大 16 個の symbol matrix を保持します。QR の容量上限とは別の、恣意的な payload size の打切りはありません。実行時に JavaScript、Node、network service、第三者の QR encoder は使用しません。

## Verification and fixture regeneration

`StructuredAppendTests` は、固定した JavaScript との差分検証 22 ケースで、**すべての matrix module** と分割 metadata を確認します。四つの ECC level 全部、固定・自動 version、version 10 と 27 での count-width band、Unicode scalar、最適化あり・なしの auto mode、manual の分割不能な segment、binary chunk、全 16 part の集合を対象とします。

追加テストでは、parity、破損した part や不完全な集合の再結合、未対応の option、空・単一の入力、分割不能な segment の overflow、大きな入力の preflight、data slice、値の独立性、error message、および決定的な乱数で作った 2,720 個の prefix で incremental tracker と core が一致することを確認します。

fixture の再生成は開発者向けの操作で、Node と、固定した upstream commit の変更のない checkout が必要です。

```sh
node Scripts/generate-structured-append-fixtures.mjs /path/to/SpecQR-JS
swift test --filter StructuredAppendTests
```

generator は、fixture file を書き出す前に、upstream の package version と commit、および追跡対象の source/fixture に変更がないことを検証します。テストと Swift package に Node のインストールは不要です。
