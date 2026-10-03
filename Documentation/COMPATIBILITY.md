# 互換性と意図的な安全上の差分

基準は SpecQR JavaScript 3.0.0-rc.2 の commit
`15ad15e5c770ea0e39072f8f88b2733018f02ffd` です。

## FNC1 の literal `%`

QR の FNC1 alphanumeric mode では単一 `%` は group separator (U+001D)、
`%%` は literal `%` として読まれます。通常の GS1 element string の literal `%` を
そのまま alphanumeric segments にすると、元の文字列を復元できません。

pinned JavaScript の high-level auto mode にはこのケースがあります。
独立した ZXing decoder で、入力 `10ABC%DEF` が `10ABC\u001DDEF`、
`10ABC%%DEF` が `10ABC%DEF` と読まれることを確認しました。
Swift の安全な既定値では、この誤変換を引き継ぎません。

### Swift の high-level raw text API

`gs1: true` または `fnc1Second` options を指定した text input について:

- literal `%` を含む auto mode は byte mode を選択し、元の UTF-8 bytes を保持する
- `optimizeSegments: false` でも同じ安全な選択をする
- 明示的な byte mode はそのまま使用する
- 明示的 alphanumeric mode と literal `%` の組み合わせは error を返す
- numeric / Kanji mode の文字種検証は変更しない
- `estimate` と `generate` は同じ判断を使い、byte mode で容量不足なら正しく報告する

manual segments に `gs1` / `fnc1Second` options を追加する API でも、
alphanumeric segment の `%` は曖昧なため拒否します。byte segment を使うか、
次の低レベル contract を明示的に選んでください。

### 低レベル control segments

caller が `.fnc1` / `.fnc1Second("A")` を segment array 内に明示する場合は
既に符号化モードを管理しているため、QR 標準の escaped alphanumeric semantics を
保持します。単一 `%` は separator、`%%` は literal `%` です。
このルートでは library が payload を書き換えません。

```swift
// raw GS1 text: literal % をそのまま保持
let safe = try SpecQR.generate("10ABC%DEF", options: .init(gs1: true))

// low-level: caller が % escaping を管理し、decoded text は 10ABC%DEF
let explicit = try SpecQR.generate(segments: [.fnc1, .alphanumeric("10ABC%%DEF")])
```

この差分で高レベル入力の Version / bit length / matrix が JS と異なる場合があります。
通常の QR、literal `%` を含まない FNC1 入力、低レベル明示 segments の差分検証は
従来どおりです。安全性の regression は matrix 比較だけでなく、独立 decoder で
元の literal `%`、繰り返し `%`、U+001D、binary bytes の一致を確認します。

## Swift 固有の API shape

- output polymorphism の代わりに immutable `QRCode` と描画 methods
- options と enum による型検証、`Error` / `throws` による失敗
- matrix-only planning と render diagnostics を分離
- Node Buffer / browser Blob は Foundation Data、DOM canvas は portable protocol
- Structured Append symbols は常に `[QRCode]`、詳細 split units は明示要求時のみ

これらは機能を削るための差分ではなく、Swift 側で同じ処理を利用するための表現です。
