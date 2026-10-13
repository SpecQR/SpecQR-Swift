# 検証結果 — 2026-10-03

## 判定

Linux 上の実装・差分・独立 decode・minimum Swift 検証は完了しています。
独立 code review に未解決の blocking source defect はありません。

macOS 27.0 / Apple Swift 6.4 で library・CLI・独立 consumer の debug/release build/run、
Core Graphics / ImageIO / Vision の独立 Swift Testing 検証まで完了しました。
初回の Command Line Tools では XCTest がなく元の suite は停止しましたが、ユーザー承認後に
導入した Xcode 27.0 で、元の macOS suite も debug/release 各 54 XCTest +2 Swift Testing、
失敗 0 で実行しました。iOS / tvOS / watchOS の実 SDK による 8 compile-only lanes も成功しています。
iOS 27.0 simulator でも debug/release 各 54 XCTest +2 Swift Testing、失敗 0・skip 0 で実行しました。
Vision test はこの simulator で対応する revision 2 + CPU を明示しています。default revision の制限は
下記に記録し、device / physical camera / print の実行とは区別します。
初回公開はこの検証範囲と制限を明示したソース公開です。全プラットフォーム・全 scanner への
無条件の適合や stable release を保証するものではありません。

## 実行済み

| 検証 | 実行結果 |
|---|---|
| Swift 6.4.0 Linux debug/release | 各 53 XCTest +2 Swift Testing、失敗 0 |
| Swift 6.0.3 Linux debug/release build/test | 同じ 55 tests、失敗 0、compiler warning 0 |
| 最終 `Scripts/verify-all.sh` | exit 0。全外部検証まで実行 |
| 独立 consumer package | release build/run 成功、public API のみ使用 |
| package dependencies | `swift package describe` で空配列 |
| fixed QR differential | 1,280 cases、V1–40 ×4 ECC ×8 masks、matrix/codewords 一致 |
| auto / control / ECC boost | 136 cases、pinned JS 一致 |
| capacity/planning boundaries | 288 cases |
| invalid inputs | 15 baseline cases |
| FNC1 safety correction | 16 intentional-divergence checks |
| SVG/PNG/data URL | 11 byte-exact render cases |
| Nayuki independent encoder | 960 complete matrix comparisons |
| jsQR independent decoder | 12 ordinary payload cases |
| GS1 helpers | 1,411 exact JSON oracle cases、50 AI 全件を含む |
| Structured Append | 22 complete-matrix/split-diagnostic fixtures |
| split tracker | package 2,720 randomized prefix checks、独立 review 1,800 追加 checks |
| matrix primitive review | 1,440 matrix/penalty comparisons、auto mask を含む |
| independent randomized review | 700 additional complete matrices |
| concurrency | 96 concurrent generate/render/GS1 tasks、value isolation |
| resource limits | Version 40、7,089 digits、oversized preflight、render integer overflow/budgets |
| Linux library line coverage | 3,006/3,176 lines (94.65 %); Apple 条件分岐は対象外 |
| formatting | 3-space Swift formatting、strict lint 成功 |
| macOS library / CLI | Apple Swift 6.4、macOS 27.0 SDK、arm64 debug/release build 成功 |
| macOS source-package consumer | `Examples/Basic` debug/release build/run 成功 |
| macOS 独立 Swift Testing | 各 10 tests /2 suites、失敗 0。元の XCTest suite とは別 |
| Core Graphics / ImageIO | straight RGBA、alpha、storage lifetime、4 full-pixel PNG roundtrips |
| Apple Vision | 各 configuration で 17 decode checks。CGImage/PNG、Unicode、GS1 `%` / separator の元 bytes 一致 |
| macOS fixtures / regressions | 1,411 GS1、22 Structured Append、FNC1 両形式、render limits、32 concurrent renders |
| Intel macOS 13 target | x86_64 library cross-compile 成功。Intel 上の実行ではない |
| Mac で見つけた 2 修正の Linux 再検証 | Swift 6.0.3/6.4 debug/release 各 55 tests、consumer、全外部 aggregate 成功 |
| Xcode macOS 元の package suite | Xcode 27.0 / Apple Swift 6.4、debug/release 各 54 XCTest +2 Swift Testing、失敗 0。条件付き Core Graphics/Vision test を含む |
| Xcode macOS source-package consumer | `Examples/Basic` release build/run 成功 |
| Xcode macOS 独立 Swift Testing 再実行 | debug/release 各 10 tests /2 suites、失敗 0。Core Graphics/ImageIO/Vision と全 fixtures を再確認 |
| iOS SDK compile | iOS 27.0 SDK、arm64 / minimum iOS 16.0、debug/release 成功 |
| tvOS SDK compile | tvOS 27.0 SDK、arm64 / minimum tvOS 16.0、debug/release 成功 |
| watchOS SDK compile | watchOS 27.0 SDK、arm64_32 / minimum watchOS 9.0、debug/release 成功。32-bit 修正を実 SDK で確認 |
| watchOS arm64 追加 compile | debug/release 成功。ただし生成 Mach-O の minimum は watchOS 26.0。watchOS 9 arm64 の結果とは扱わない |
| iOS simulator 元の package suite | iOS 27.0 /24A434、iPhone 17 arm64、debug/release 各 54 XCTest +2 Swift Testing、失敗 0・skip 0。Vision は revision 2 + CPU |
| iOS simulator Vision 対照 probe | 40 実 decode attempts: 19 件 payload 一致、20 件 observation なし、1 件 inference error。全件成功ではない。Apple CoreImage 生成 QR も比較 |

上記の case 数は suite 内の検証件数であり、Linux の 55 methods や macOS/iOS simulator の 56 methods に単純加算した
「総テスト数」ではありません。複数 lanes には重複した入力も含まれます。
Apple 独立 suite の 10 methods には fixture 件数と decode checks を含み、別加算しません。

初回 CLT 環境・実行ログ・再現 script は [Apple evidence](evidence/apple/README.md)、
後続の Xcode 実行結果は [Xcode evidence](evidence/xcode/README.md) を参照してください。
SDK lanes は library の source compile で、link / deploy / signing / device 実行ではありません。
各 object の architecture と minimum OS は [SDK evidence](evidence/xcode/sdk/README.txt) に記録しています。
Mac で確認した consumer deployment minimum と 32-bit integer literal の修正は、
[同一 source の Linux 再検証](evidence/mac-fix-linux-validation/README.txt) でも確認しました。

<a name="ios-simulatorのvision構成と制限"></a>

## iOS simulator の Vision 構成と制限

iOS 27.0 /24A434 の default Vision revision 4 は、最初の test で `com.apple.Vision Code9`
(`Could not create inference context`) を返しました。独立した 40-case probe では、
revision 3/4 は SpecQR の既定 296 px 画像・拡大画像と Apple CoreImage 生成 QR のいずれも
observation を返しませんでした。revision 1 および revision 2 + 対応 CPU では元 payload を復元しました。
この対照結果は当該 simulator の Vision 制限を示し、SpecQR renderer の defect を確立するものではありません。

最終 test では iOS simulator 分岐だけで、deprecated だがこの runtime の supported revisions に含まれる
`VNDetectBarcodesRequestRevision2` と対応 CPU を選択しました。既定の生成画像、実際の
`VNImageRequestHandler.perform`、payload 完全一致 assertion は維持し、失敗の skip や握り潰しはありません。
default revision 4 が成功したとは扱いません。macOS では default request を維持しています。
詳細・全 40 結果は [Vision probe](evidence/xcode/vision-probe/README.txt) を参照してください。
変更は Apple test の iOS simulator 分岐のみで、runtime source と既存 Linux 再検証の対象 source は同一です。

## 独立 decoder と metadata

ZXing Java 3.5.4:

- 実際の Swift PNG を ImageIO → binarizer → finder detection → decode: 419 symbols
- direct matrix decode: 419 symbols
- Structured Append の合法 index/total 組み合わせ 135 通り
- high-level 6 sets/48 symbols。16-symbol set、全 256 byte 値、Unicode、manual mixed を含む
- decoded metadata から順不同の parts を再結合し、元の text/bytes/parity を照合
- 32 symbols について、異なる 3 data codewords を破損させて正確に復元
- all-white invalid symbol を拒否

ZXing-C++ 3.1.1:

- FNC1-second の合法 application indicators 152 通り、608 symbols
- high-level GS1/FNC1-second の literal `%` / `%%` / U+001D、32 cases
- auto/byte、optimization on/off、low-level escaping、binary bytes を照合

Java decoder は FNC1-second indicator を正しく消費しないため、その mode は
C++ decoder で別途検証しています。ECI の実 decoder 検証は 3/20/26/170。
全 ECI assignment の decoder 対応は保証しません。

## 意図的な baseline 差分

high-level GS1/FNC1 raw text の literal `%` を勝手に separator に変換しないため、
auto は byte mode に切り替え、明示 alphanumeric は guidance 付きで拒否します。
詳細と low-level contract は [COMPATIBILITY.md](COMPATIBILITY.md)。
この修正は独立 decoder の元 payload 一致で検証済みです。

## 未実施 / 制限

- iOS 27.0 simulator の default Vision revision 3/4 は上記対照 probe で decode 不成立。最終 suite 成功は revision 2 + CPU 構成に限定
- iOS / tvOS / watchOS の device 実行、link / deploy / signing。SDK compile 成功とは区別する
- 宣言 deployment minimum の実 OS、Intel / その他 CPU 上の実行
- Swift 6.0 系列は 6.0.3 で検証。6.0.0 binary そのものは未使用
- 保存済みのローカル検証 evidence には remote CI 実行結果を含めない。公開後の各 commit の結果は [GitHub Actions](https://github.com/SpecQR/SpecQR-Swift/actions) を参照
- physical camera、印刷物、全ての damage patterns、全 scanner metadata 実装
- ISO / GS1 の適合認証、完全な GS1 AI catalog、暦としての日付検証
- 以前作成された Swift archives は取得できず、この実装では使用していない

## 再現手順

```sh
swift test
swift test -c release
swift run --package-path Examples/Basic -c release
./Scripts/verify-apple.sh  # macOSの独立Swift Testing lane。元のXCTest suiteの代替ではない
./Scripts/verify-all.sh
```

通常 tests はネットワーク不要。全外部検証には Swift、Node 20+、Java 17+ compiler module、
Python 3.10+ と pip、curl、GitHub/Maven Central/PyPI/npm への読み取り接続が必要です。
macOS の元の XCTest suite は full Xcode の developer directory を選択して実行します。
第三者依存は検証用のみで runtime には含みません。pinned versions/hashes は
[decoder 手順](../Scripts/zxing-java/README.md) と [provenance](PROVENANCE.md) を参照。

実行ログと source/binary hashes は [evidence](evidence/README.md)。
versioned release に向けた残作業は [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)。
