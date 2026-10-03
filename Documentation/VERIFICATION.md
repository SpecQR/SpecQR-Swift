# 検証結果 — 2026-10-03

## 判定

Linux 上の実装・差分・独立 decode・minimum Swift 検証は完了しています。
独立 code review に未解決の blocking source defect はありません。

macOS 27.0 / Apple Swift 6.4 で library・CLI・独立 consumer の debug/release build/run、
Core Graphics / ImageIO / Vision の独立 Swift Testing 検証まで完了しました。
初回の Command Line Tools では XCTest がなく元の suite は停止しましたが、ユーザー承認後に
導入した Xcode 27.0 で、元の macOS suite も debug/release 各54 XCTest +2 Swift Testing、
失敗0で実行しました。iOS / tvOS / watchOS の実SDKによる8 compile-only lanesも成功しています。
iOS27.0 simulatorでもdebug/release各54 XCTest +2 Swift Testing、失敗0・skip0で実行しました。
Vision testはこのsimulatorで対応するrevision2 + CPUを明示しています。default revisionの制限は
下記に記録し、device / physical camera / print の実行とは区別します。
初回公開はこの検証範囲と制限を明示したソース公開です。全プラットフォーム・全scannerへの
無条件の適合やstable releaseを保証するものではありません。

## 実行済み

| 検証 | 実行結果 |
|---|---|
| Swift6.4.0 Linux debug/release | 各53 XCTest +2 Swift Testing、失敗0 |
| Swift6.0.3 Linux debug/release build/test | 同じ55 tests、失敗0、compiler warning0 |
| 最終 `Scripts/verify-all.sh` | exit0。全外部検証まで実行 |
| 独立 consumer package | release build/run 成功、public API のみ使用 |
| package dependencies | `swift package describe` で空配列 |
| fixed QR differential | 1,280 cases、V1–40 ×4 ECC ×8 masks、matrix/codewords一致 |
| auto / control / ECC boost | 136 cases、pinned JS一致 |
| capacity/planning boundaries | 288 cases |
| invalid inputs | 15 baseline cases |
| FNC1 safety correction | 16 intentional-divergence checks |
| SVG/PNG/data URL | 11 byte-exact render cases |
| Nayuki independent encoder | 960 complete matrix comparisons |
| jsQR independent decoder | 12 ordinary payload cases |
| GS1 helpers | 1,411 exact JSON oracle cases、50 AI全件を含む |
| Structured Append | 22 complete-matrix/split-diagnostic fixtures |
| split tracker | package2,720 randomized prefix checks、独立review1,800追加checks |
| matrix primitive review | 1,440 matrix/penalty comparisons、auto maskを含む |
| independent randomized review | 700 additional complete matrices |
| concurrency | 96 concurrent generate/render/GS1 tasks、value isolation |
| resource limits | Version40、7,089digits、oversized preflight、render integer overflow/budgets |
| Linux library line coverage | 3,006/3,176 lines (94.65%); Apple条件分岐は対象外 |
| formatting | 3-space Swift formatting、strict lint成功 |
| macOS library / CLI | Apple Swift6.4、macOS27.0 SDK、arm64 debug/release build成功 |
| macOS source-package consumer | `Examples/Basic` debug/release build/run成功 |
| macOS 独立 Swift Testing | 各10 tests /2 suites、失敗0。元の XCTest suiteとは別 |
| Core Graphics / ImageIO | straight RGBA、alpha、storage lifetime、4 full-pixel PNG roundtrips |
| Apple Vision | 各configurationで17 decode checks。CGImage/PNG、Unicode、GS1 `%` / separatorの元bytes一致 |
| macOS fixtures / regressions | 1,411 GS1、22 Structured Append、FNC1両形式、render limits、32 concurrent renders |
| Intel macOS13 target | x86_64 library cross-compile成功。Intel上の実行ではない |
| Macで見つけた2修正のLinux再検証 | Swift6.0.3/6.4 debug/release各55 tests、consumer、全外部aggregate成功 |
| Xcode macOS 元のpackage suite | Xcode27.0 / Apple Swift6.4、debug/release各54 XCTest +2 Swift Testing、失敗0。条件付きCore Graphics/Vision testを含む |
| Xcode macOS source-package consumer | `Examples/Basic` release build/run成功 |
| Xcode macOS 独立Swift Testing再実行 | debug/release各10 tests /2 suites、失敗0。Core Graphics/ImageIO/Visionと全fixturesを再確認 |
| iOS SDK compile | iOS27.0 SDK、arm64 / minimum iOS16.0、debug/release成功 |
| tvOS SDK compile | tvOS27.0 SDK、arm64 / minimum tvOS16.0、debug/release成功 |
| watchOS SDK compile | watchOS27.0 SDK、arm64_32 / minimum watchOS9.0、debug/release成功。32-bit修正を実SDKで確認 |
| watchOS arm64追加compile | debug/release成功。ただし生成Mach-OのminimumはwatchOS26.0。watchOS9 arm64の結果とは扱わない |
| iOS simulator 元のpackage suite | iOS27.0 /24A434、iPhone17 arm64、debug/release各54 XCTest +2 Swift Testing、失敗0・skip0。Visionはrevision2 + CPU |
| iOS simulator Vision対照probe | 40実decode attempts: 19件payload一致、20件observationなし、1件inference error。全件成功ではない。Apple CoreImage生成QRも比較 |

上記の case 数は suite 内の検証件数であり、Linuxの55 methodsやmacOS/iOS simulatorの56 methodsに単純加算した
「総テスト数」ではありません。複数 lanes には重複した入力も含まれます。
Apple独立suiteの10 methodsにはfixture件数とdecode checksを含み、別加算しません。

初回CLT環境・実行ログ・再現scriptは [Apple evidence](evidence/apple/README.md)、
後続のXcode実行結果は [Xcode evidence](evidence/xcode/README.md)を参照してください。
SDK lanesはlibraryのsource compileで、link / deploy / signing / device実行ではありません。
各objectのarchitectureとminimum OSは [SDK evidence](evidence/xcode/sdk/README.txt)に記録しています。
Macで確認したconsumer deployment minimumと32-bit integer literalの修正は、
[同一sourceのLinux再検証](evidence/mac-fix-linux-validation/README.txt)でも確認しました。

## iOS simulatorのVision構成と制限

iOS27.0 /24A434のdefault Vision revision4は、最初のtestで `com.apple.Vision Code9`
(`Could not create inference context`) を返しました。独立した40-case probeでは、
revision3/4はSpecQRの既定296px画像・拡大画像とApple CoreImage生成QRのいずれも
observationを返しませんでした。revision1およびrevision2 + 対応CPUでは元payloadを復元しました。
この対照結果は当該simulatorのVision制限を示し、SpecQR rendererのdefectを確立するものではありません。

最終testではiOS simulator分岐だけで、deprecatedだがこのruntimeのsupported revisionsに含まれる
`VNDetectBarcodesRequestRevision2` と対応CPUを選択しました。既定の生成画像、実際の
`VNImageRequestHandler.perform`、payload完全一致assertionは維持し、失敗のskipや握り潰しはありません。
default revision4が成功したとは扱いません。macOSではdefault requestを維持しています。
詳細・全40結果は [Vision probe](evidence/xcode/vision-probe/README.txt)を参照してください。
変更はApple testのiOS simulator分岐のみで、runtime sourceと既存Linux再検証の対象sourceは同一です。

## 独立 decoder と metadata

ZXing Java 3.5.4:

- 実際の Swift PNG を ImageIO → binarizer → finder detection → decode: 419 symbols
- direct matrix decode: 419 symbols
- Structured Append の合法 index/total 組み合わせ135通り
- high-level6sets/48symbols。16-symbol set、全256 byte値、Unicode、manual mixedを含む
- decoded metadata から順不同の parts を再結合し、元の text/bytes/parity を照合
- 32symbolsについて、異なる3 data codewords を破損させて正確に復元
- all-white invalid symbol を拒否

ZXing-C++ 3.1.1:

- FNC1-second の合法 application indicators152通り、608symbols
- high-level GS1/FNC1-second の literal `%` / `%%` / U+001D、32cases
- auto/byte、optimization on/off、low-level escaping、binary bytes を照合

Java decoder は FNC1-second indicator を正しく消費しないため、その mode は
C++ decoder で別途検証しています。ECI の実 decoder 検証は3/20/26/170。
全ECI assignmentの decoder対応は保証しません。

## 意図的な baseline 差分

high-level GS1/FNC1 raw text の literal `%` を勝手に separator に変換しないため、
auto は byte mode に切り替え、明示 alphanumeric は guidance付きで拒否します。
詳細と low-level contract は [COMPATIBILITY.md](COMPATIBILITY.md)。
この修正は独立 decoder の元payload一致で検証済みです。

## 未実施 / 制限

- iOS27.0 simulatorのdefault Vision revision3/4は上記対照probeでdecode不成立。最終suite成功はrevision2 + CPU構成に限定
- iOS / tvOS / watchOS のdevice実行、link / deploy / signing。SDK compile成功とは区別する
- 宣言 deployment minimum の実 OS、Intel / その他CPU上の実行
- Swift6.0系列は6.0.3で検証。6.0.0 binaryそのものは未使用
- GitHub Actions workflow は用意しただけで、remote実行はしていない
- physical camera、印刷物、全ての damage patterns、全scanner metadata実装
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

通常 tests はネットワーク不要。全外部検証には Swift、Node20+、Java17+ compiler module、
Python3.10+とpip、curl、GitHub/Maven Central/PyPI/npmへの読み取り接続が必要です。
macOSの元のXCTest suiteはfull Xcodeのdeveloper directoryを選択して実行します。
第三者依存は検証用のみで runtimeには含みません。pinned versions/hashesは
[decoder手順](../Scripts/zxing-java/README.md)と [provenance](PROVENANCE.md) を参照。

実行ログと source/binary hashes は [evidence](evidence/README.md)。
versioned releaseに向けた残作業は [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)。
