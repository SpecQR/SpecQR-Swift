# GS1 helpers

GS1 helper は代表 50 AI の解析・検証・check digit・Digital Link を提供します。
全 GS1 規格の認証機能ではありません。高レベル QR 生成では literal `%` を保持する
[安全上の互換差分](COMPATIBILITY.md) があります。以下は型名と厳密な挙動の参照です。

`GS1` は依存パッケージのない公開 namespace で、URL authority と IDNA の処理に Foundation を使用します。要素の解析、AI catalog、check digit、Digital Link の配置、検証の挙動は、upstream SpecQR **3.0.0-rc.2**、commit `15ad15e5c770ea0e39072f8f88b2733018f02ffd` に従います。GS1 規格の完全な網羅は、意図的に**主張していません**。

公開する入出力の value types はすべて `Sendable` です。要素と dictionary metadata は変更不能で、`Equatable` と `Codable` に準拠します。AI と値はどちらも文字列なので、要素の先頭のゼロは維持されます。

## Parse, generate, and validate

```swift
import SpecQR

let elements = try GS1.parseHumanReadable(
    "(01)04912345678904(10)ABC123(17)251231"
)
let raw = try GS1.createElementString(elements)
// "010491234567890410ABC123\u{1D}17251231"

let parsed = try GS1.parseElementString(raw)
print(parsed.elements)
print(parsed.hasSeparators) // true

let checked = GS1.validateElements(elements)
if !checked.ok {
    for issue in checked.errors {
        print(issue.code, issue.message, issue.ai as Any)
    }
}
```

`createElementString` は、後続の要素がある場合に限り、可変長要素の後へ `GS1.fnc1Separator`（ASCII GS、U+001D）を挿入します。`parseHumanReadable` は連続する `(AI)value` の組を受け取り、実際の値に含まれるもの以外に、先頭や要素間の整形用空白がないことを前提とします。raw parser は、human-readable 形式の括弧、未対応の AI、不正な値、先頭・末尾・不要な separator、曖昧な末尾の可変長値を拒否します。

raw parser は upstream の保守的な曖昧性判定を意図的に維持しています。末尾の可変長値の接尾部が完全な固定長要素に見える場合、`GS1_MISSING_SEPARATOR` で拒否します。このため、そのような接尾部を含む literal な batch/serial も拒否されることがあります。曖昧と判定する前に、候補の接尾部の内容や check digit は検証しません。

throw する helper は `GS1Error` を使用し、その `code` は `"INVALID_GS1"`、`message` は問題の内容を示します。`validateElements`、`validateElementString`、`validateDigitalLink` は、throw せずに構造化した結果を返します。失敗時の結果には error が含まれ、正常に解析された要素や結果は含まれません。error の field には `code`、`message`、`reason` と、該当する場合の `ai`、`value`、`offset`、`elementIndex`、`key`、`expected` があります。offset は upstream JavaScript API と同じく UTF-16 code units で数えます。検証結果は `Encodable` に準拠し、成功時・失敗時の JSON shape は upstream と互換です。

```swift
let checked = GS1.validateElements(elements, options: .init(
    context: .digitalLink,
    collectAllErrors: false
))
```

- **要素配列**の検証で `context: .digitalLink` を指定すると、少なくとも一つの primary AI（`00`、`01`、`414` のいずれか）が必要になります。AI の重複や URI の path 配置規則のすべては検証しません。それらの検証には Digital Link helper を使用してください。
- **raw string** の検証は、upstream と同じくこれらの option を受け取りますが、Digital Link context の検証は適用しません。最初の parser error で停止します。
- `allowUnsupportedAI: true` を指定すると、option が不正であることを示す issue を返します。未知の AI を受け入れることはありません。
- Swift の厳密な enum 型により、JavaScript でのみ指定できる不正な option の型や context 文字列は排除されます。

## Supported AI metadata

```swift
let all = GS1.getSupportedAIs() // 50 concrete AIs, in stable upstream order
let batch = GS1.getAIInfo("10")
let unsupported = GS1.getAIInfo("3106") // nil
```

個別の AI: `00`、`01`、`02`、`10`、`11`、`12`、`13`、`15`、`16`、`17`、`20`、`21`、`22`、`30`、`37`、`240`、`241`、`400`、`410`、`411`、`412`、`413`、`414`、`415`、`420`、`422`、`424`、`425`、`426`。

展開する AI family: `3100`–`3105`、`3200`–`3205`、`91`–`99`。

`AIInfo` には label、固定長または可変長の `length`、`valueKind`、`checkDigitRule`、`digitalLinkRole`、許可される qualifier と primary の関係、separator の要否が含まれます。値はすべて空でない印字可能な ASCII とし、括弧や GS separator を含めてはいけません。数字用の AI には ASCII の十進数字が必要です。日付は数字 6 文字で、**暦としての有効性は検証しません**。primary AI `414` を含む GLN field は、この upstream catalog では check digit の検証を**受けません**。この移植版でも、それらの制約を暗黙には追加しません。

## Check digits

```swift
try GS1.calculateCheckDigit("0491234567890")        // "4"
try GS1.validateCheckDigit("04912345678904")        // true
try GS1.calculateGTINCheckDigit("0491234567890")    // "4"
try GS1.appendGTINCheckDigit("0491234567890")       // "04912345678904"
try GS1.validateGTINCheckDigit("04912345678905")    // false
try GS1.calculateSSCCCheckDigit("12345678901234567") // "5"
try GS1.appendSSCCCheckDigit("12345678901234567")  // "123456789012345675"
try GS1.validateSSCCCheckDigit("123456789012345675") // true
```

GTIN の本体は 7、11、12、13 桁、check digit を含む完全な GTIN は 8、12、13、14 桁を受け入れます。SSCC の本体は 17 桁、完全な SSCC は 18 桁が必要です。形式が正しく check digit が不正な値には false を返し、形式が不正な入力では throw します。汎用の計算 helper は、空でない任意の ASCII 数字の本体を受け入れます。汎用の検証 helper には、本体と一つの check digit が必要です。

## GS1 Digital Link

```swift
let uri = try GS1.createDigitalLink(elements, options: .init(
    baseURL: "https://example.com/stem"
))
// https://example.com/stem/01/04912345678904/10/ABC123?17=251231

let parsedLink = try GS1.parseDigitalLink(uri)
let validLink = GS1.validateDigitalLink(uri)
let normalized = try GS1.normalizeDigitalLink(uri)
```

builder は `[GS1.Element]`、`ElementStringParseResult`、`DigitalLinkParseResult` を受け入れます。最後の型から未知の query parameter を暗黙に再追加することはありません。正規化では、それらを明示的に保持します。明示する `baseURL` には文字列または Foundation `URL` を指定でき、解析・検証・正規化も両方の表現を受け入れます。

`DigitalLinkOptions`:

- `baseURL`: 必須。絶対 HTTP または HTTPS URL とし、空でない query や fragment を含めてはいけません。
- `primaryAI`: `.gtin`（`01`、既定値）、`.sscc`（`00`）、または `.gln`（`414`）。
- `pathAIs`: nil では対象となる qualifier を自動選択します。`[]` では primary 以外の全要素を query に配置します。明示した配列では、許可された qualifier を選択します。

path qualifier に対応するのは AI `10`、`21`、`22` だけで、primary `01` の後に限ります。対象となる qualifier は入力順を維持します。query の AI は辞書順に並べます。path と GS1 query を通して、すべての AI は一意である必要があります。ほかの primary AI は、path の primary として選択されていなければ、upstream と同じく query attribute に使用できます。

解析では最初の primary AI segment を探し、その前の stem を保持します。解析 option の `primaryAI` は、探索対象をその primary に限定します。query の値には form decoding（`+` は空白）を使い、path の値には URI component decoding（`+` はプラスのまま）を使います。重複した未知の query key とその順序は `unknownQuery` に保持します。既定の方針は `.preserve` です。`.reject` では AI 以外の query key をすべて拒否します。

```swift
let parsed = try GS1.parseDigitalLink(uri, options: .init(
    primaryAI: .gtin,
    unknownQuery: .reject
))
```

throw しない URI 検証では、HTTP の使用と、保持した未知の query parameter を警告として報告します。構文が不正な percent escape は解析前に拒否します。path の decode は厳密な UTF-8 で行い、未知の query の値は upstream の寛容な form decoding に従います。空の `?`/`#` component は upstream と同じ挙動です。空でない fragment は拒否します。

`normalizeDigitalLink` は **SpecQR の決定的な正規化**を行い、GS1 の完全な canonicalization は行いません。対象となる GS1 qualifier を query から path へ移し、path qualifier の順序を維持し、残る GS1 query parameter を並べ替え、未知の parameter を元の相対順序で末尾に追加します。正しい builder 出力に対しては冪等です。受け入れる正規化の `mode` は `"specqr-deterministic"` だけです。`normalize: true` を `DigitalLinkValidationOptions` に渡すと、upstream の未対応 option の issue を返します。代わりに normalizer を呼び出してください。

URL 処理には、percent の保持と正規化、IDNA、既定 port、省略形・十六進・八進の IPv4 表記、IPv6 圧縮、dot segment、upstream の WHATWG URL 処理が受け入れる special-scheme 構文が含まれます。これは Digital Link に用途を絞った URL adapter であり、ブラウザーの URL 実装を汎用的に置き換えるものではありません。

## Differential tests

`GS1Tests` は、固定した upstream JavaScript 実装から生成した fixture と、値全体および構造化した失敗結果を比較します。対象は catalog 全体、すべての check digit helper、不正な値と separator、option の挙動、path/query の役割、qualifier の順序、escape、未知の query の保持、URI の正規化、数字の host、IPv6、IDNA、不正な UTF-8、範囲を超える port です。

固定した checkout を `../upstream` に配置し、package の root で実行します。

```sh
node Scripts/generate-gs1-fixtures.mjs ../upstream
swift test --filter GS1Tests
```

fixture generator は、第 1 引数に別の upstream checkout を指定できます。移植可能で repository に収録した `Tests/SpecQRTests/Fixtures/gs1-upstream.json` resource を書き出します。通常の Swift tests に Node や upstream checkout は不要です。
