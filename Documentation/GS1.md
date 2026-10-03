# GS1 helpers

GS1 helper は代表 50 AI の解析・検証・check digit・Digital Link を提供します。
全 GS1 規格の認証機能ではありません。高レベル QR 生成では literal `%` を保持する
[安全上の互換差分](COMPATIBILITY.md)があります。以下は型名と厳密な挙動の参照です。

`GS1` is a dependency-free public namespace using Foundation for URL authority and IDNA handling. Its element parsing, AI catalog, check digits, Digital Link placement, and validation behavior follow upstream SpecQR **3.0.0-rc.2**, commit `15ad15e5c770ea0e39072f8f88b2733018f02ffd`. It deliberately does **not** claim complete GS1 standards coverage.

All public input/output value types are `Sendable`. Elements and dictionary metadata are immutable, `Equatable`, and `Codable`. Elements retain leading zeroes because both AI and value are strings.

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

`createElementString` inserts `GS1.fnc1Separator` (ASCII GS, U+001D) after a variable-length element only when another element follows. `parseHumanReadable` expects consecutive `(AI)value` pairs, with no leading or inter-element formatting whitespace beyond the actual value. The raw parser rejects human-readable parentheses, unsupported AIs, invalid values, leading/trailing/unnecessary separators, and ambiguous final variable-length values.

The raw parser intentionally retains upstream's conservative ambiguity heuristic: a final variable-length value whose suffix looks like a complete fixed-length element is rejected with `GS1_MISSING_SEPARATOR`. This can reject a literal batch/serial containing such a suffix. It does not validate that candidate suffix's content or check digit before declaring ambiguity.

Throwing helpers use `GS1Error`, whose `code` is `"INVALID_GS1"` and whose `message` identifies the problem. `validateElements`, `validateElementString`, and `validateDigitalLink` return structured, nonthrowing results. On failure, results contain errors and no successful parsed elements/result. Error fields include `code`, `message`, `reason`, and applicable `ai`, `value`, `offset`, `elementIndex`, `key`, and `expected`. Offsets count UTF-16 code units, as in the upstream JavaScript API. Validation results conform to `Encodable` with upstream-compatible success/failure JSON shapes.

```swift
let checked = GS1.validateElements(elements, options: .init(
    context: .digitalLink,
    collectAllErrors: false
))
```

- `context: .digitalLink` on **element-array** validation requires at least one primary AI (`00`, `01`, or `414`). It does not check duplicate AIs or all URI path-placement rules; use the Digital Link helpers for those checks.
- As upstream does, **raw-string** validation accepts these options but does not apply the Digital Link context check. It stops at the first parser error.
- Setting `allowUnsupportedAI: true` produces an invalid-options issue. Unknown AIs are never accepted.
- Strongly typed Swift enums rule out JavaScript-only invalid option types/context strings.

## Supported AI metadata

```swift
let all = GS1.getSupportedAIs() // 50 concrete AIs, in stable upstream order
let batch = GS1.getAIInfo("10")
let unsupported = GS1.getAIInfo("3106") // nil
```

Exact AIs: `00`, `01`, `02`, `10`, `11`, `12`, `13`, `15`, `16`, `17`, `20`, `21`, `22`, `30`, `37`, `240`, `241`, `400`, `410`, `411`, `412`, `413`, `414`, `415`, `420`, `422`, `424`, `425`, `426`.

Expanded families: `3100`–`3105`, `3200`–`3205`, `91`–`99`.

`AIInfo` includes the label, fixed or variable `length`, `valueKind`, `checkDigitRule`, `digitalLinkRole`, allowed qualifier-primary relationships, and separator requirement. All values must be nonempty printable ASCII, without parentheses or GS separators. Numeric AIs require ASCII decimal digits. Dates are six numeric characters, **not calendar-validated**. GLN fields, including primary AI `414`, do **not** receive a check-digit check in this upstream catalog. The port does not silently add those restrictions.

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

GTIN bodies accept 7, 11, 12, or 13 digits; complete GTINs accept 8, 12, 13, or 14. SSCC bodies require 17 digits and complete SSCCs require 18. A correctly shaped value with an incorrect check digit returns false; malformed input throws. The generic calculator accepts any nonempty ASCII numeric body; the generic validator requires a body and one check digit.

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

The builder accepts `[GS1.Element]`, `ElementStringParseResult`, or `DigitalLinkParseResult`. The latter does not implicitly re-add unknown query parameters; normalization explicitly preserves them. The explicit `baseURL` can be a string or Foundation `URL`; parsing, validation, and normalization also accept either representation.

`DigitalLinkOptions`:

- `baseURL`: required, absolute HTTP or HTTPS, with no nonempty query or fragment
- `primaryAI`: `.gtin` (`01`, default), `.sscc` (`00`), or `.gln` (`414`)
- `pathAIs`: nil selects eligible qualifiers automatically; `[]` places every non-primary element in the query; an explicit array chooses permitted qualifiers

Only AIs `10`, `21`, and `22` are supported path qualifiers, and only after primary `01`. Eligible qualifiers retain input order. Query AIs sort lexicographically. Every AI must be unique across the path and GS1 query. Other primary AIs can appear as query attributes if not selected as the path primary, matching upstream.

Parsing discovers the first primary AI segment, preserving a preceding stem. A `primaryAI` parse option restricts the search to that primary. Query values use form decoding (`+` means space), while path values use URI component decoding (`+` remains plus). Duplicate unknown query keys and their order are preserved in `unknownQuery`. The default policy is `.preserve`; `.reject` rejects any non-AI query key.

```swift
let parsed = try GS1.parseDigitalLink(uri, options: .init(
    primaryAI: .gtin,
    unknownQuery: .reject
))
```

Nonthrowing URI validation reports HTTP use and preserved unknown query parameters as warnings. It rejects syntactically invalid percent escapes before parsing. Path decoding is strict UTF-8; unknown query values follow upstream's forgiving form-decoding behavior. Empty `?`/`#` components behave like upstream; a nonempty fragment is rejected.

`normalizeDigitalLink` performs **SpecQR deterministic normalization**, not complete GS1 canonicalization. It moves eligible GS1 qualifiers from query to path, retains path qualifier order, sorts remaining GS1 query parameters, and appends unknown parameters in their original relative order. It is idempotent for valid builder output. The only accepted normalization `mode` is `"specqr-deterministic"`. Passing `normalize: true` to `DigitalLinkValidationOptions` returns the upstream unsupported-option issue; invoke the normalizer instead.

URL handling includes percent preservation and normalization, IDNA, default ports, abbreviated/hex/octal IPv4 forms, IPv6 compression, dot segments, and the special-scheme syntax accepted by upstream's WHATWG URL operations. This is a focused Digital Link URL adapter, not a general-purpose replacement for a browser URL implementation.

## Differential tests

`GS1Tests` compares complete values and structured failures against generated fixtures from the pinned upstream JavaScript implementation. Cases cover the entire catalog, all check-digit helpers, malformed values and separators, option behavior, path/query roles, qualifier order, escaping, unknown query preservation, URI normalization, numeric hosts, IPv6, IDNA, invalid UTF-8, and oversized ports.

From the package root, with the pinned checkout at `../upstream`:

```sh
node Scripts/generate-gs1-fixtures.mjs ../upstream
swift test --filter GS1Tests
```

The fixture generator accepts a different upstream checkout as its first argument. It writes the portable checked-in `Tests/SpecQRTests/Fixtures/gs1-upstream.json` resource; normal Swift tests do not require Node or the upstream checkout.
