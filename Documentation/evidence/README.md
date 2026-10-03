# 実行証跡

2026-10-03 に実行した検証の保存結果です。

- `verify-all.log`: 最終 aggregate command。Swift6.4 debug/release、pinned JS、Nayuki、jsQR、ZXing Java/C++
- `consumer-smoke.log`: public product のみを使用する独立 package の build/run
- `differential.json`: baseline と意図的安全差分の確認件数
- `zxing-*.json`: 最終 aggregate run が実際に検証した CLI の SHA-256 を含む
- `swift60/`: Swift6.0.3 での debug/release build/test と source manifest
- `review/`: 独立 code review、再現用 probes、実行ログ
- `apple/`: 初回CLTでのmacOS実build/run、独立Swift Testing debug/release、CoreGraphics/ImageIO/Vision、当時のXCTest失敗
- `mac-fix-linux-validation/`: Macで見つけた2修正と同一sourceのSwift6.0.3/6.4全再検証
- `xcode/`: 承認後に導入したXcode27.0での元のmacOS suite、各54 XCTest +2 Swift Testing、debug/release失敗0、consumer release実行
- `xcode/apple-validation/`: Xcodeでの独立10 tests再実行、debug/release成功、入力sourceと生成物のhash
- `xcode/sdk/`: iOS/tvOS/watchOSの実SDK source compile、8 lanes成功。architecture/minimum OSをobjectで検査
- `xcode/simulator-*-test.log`: iOS27.0 /24A434、iPhone17 arm64でdebug/release各54 XCTest +2 Swift Testing、失敗0・skip0
- `xcode/vision-probe/`: Vision40実decode attemptsの対照実験。SpecQRとApple CoreImage生成画像、全結果/errorを保存

review 自身の decoder report が参照する以前の CLI hash と、最終 aggregate build の
CLI hash は異なる場合があります。runtime source の確認は source manifest で、
実行 binary の確認は各 report の hash で区別しています。コンパイル成果物の
byte-for-byte reproducible build を保証する記録ではありません。

ログ時刻は実行 host の表示時刻です。初回Linux/CLT証跡は変更せず、修正後のLinux再検証と
後続のXcode証跡を別directoryに追加しました。`distribution-source-sha256.txt`は現在の配布source、
各runtime manifestはそのlaneの実行対象sourceを表します。初回CLTのXCTest失敗は履歴として
保持し、元のmacOS suiteが成功した証拠は`xcode/`のログで確認します。

SDK lanesはsource compileであり、device/simulator実行やlink/deploy/signingの証拠ではありません。
watchOS9のminimumはarm64_32 objectで確認済みですが、追加arm64 laneのemitted minimumは26です。
iOS simulatorは実行済みですが、Vision testはdeprecatedだがsupportedなrevision2 + 対応CPUの
構成です。default revision4の最初のinference errorと、revision3/4が両generatorの画像を
decodeできなかった対照結果も保持しています。40-case probeの内訳は19件payload一致、
20件observationなし、1件errorで、全件passとは数えません。test変更はiOS simulator分岐のみで、
runtime sourceはLinux再検証時と同一です。[Xcode evidence](xcode/README.md)と
[VERIFICATION.md](../VERIFICATION.md)で最新の実行済み・未実施を区別してください。

## Public evidence copy

This repository contains sanitized validation records. Personal filesystem prefixes,
private artifact identifiers and ephemeral device identifiers are replaced by explicit
placeholders. Raw Xcode result bundles, simulator session/process diagnostics and
installation/device inventories are excluded. Toolchain versions, commands, test
outcomes, production-source hashes and the negative Vision control results are retained.
Historical artifact/binary hashes describe the original validation outputs; they do not
claim byte identity for sanitized logs. `distribution-source-sha256.txt` identifies this
public source tree.
