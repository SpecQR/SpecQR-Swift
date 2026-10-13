# Provenance and licensing

## Canonical behavior reference

- プロジェクト: SpecQR/SpecQR（接続済みの GitHub アカウント: SpecQR）
- ソース: https://github.com/SpecQR/SpecQR
- 固定コミット: `15ad15e5c770ea0e39072f8f88b2733018f02ffd`
- コミット日: 2026-08-02
- package.json: `3.0.0-rc.2`
- License: MIT, copyright SpecQR contributors; LICENSE retained verbatim

Swift 実装は、ユーザーが指定した挙動と、固定した upstream の実際のソース、文書、
テストベクトルを基に新規作成しました。第三者の QR エンコーダー、Core Image、
web view、JavaScript は呼び出しません。QR の容量とブロック配置の定数は、
upstream プロジェクトと同じ Model 2 の表を表しています。有料の ISO 規格本文は含みません。

Kanji の対応表は、upstream の WHATWG TextDecoder の対応付けと first-hit 規則に従い、
QR で有効な Shift_JIS の範囲から生成した決定的な対応表です。生成器、対応件数、
実装ソースは Swift 実装とともに保存しています。実行時にはプラットフォームの
コーデックを使用しません。

過去の Swift アーカイブは、利用可能なファイル取得経路では取得できませんでした。
これらは変更せず、この実装の検証済みソースやテスト成功の根拠としては扱いませんでした。

## Test-only references

外部検証では、固定した upstream の package-lock.json を使用します。

- nayuki-qr-code-generator 1.8.0 (MIT): 固定 mask の matrix の完全一致を独立に検証します。
- jsqr 1.4.0 (Apache-2.0): 生成したシンボルを独立にデコードします。

ZXing Java core 3.5.4 と ZXing-C++ 3.1.1 (Apache-2.0) は、PNG/matrix のデコードと
制御メタデータを独立に検証します。バージョンと成果物の SHA-256 ハッシュは、
Scripts/verify-zxing.mjs と Scripts/zxing-java に固定しています。

これらはテスト用に Sources の外へダウンロードするもので、Swift Package の
実行時依存関係ではありません。テストランナーは出力を比較し、第三者のエンコーダーの
ソースをライブラリに取り込みません。

## Toolchain used for this work

この実装の作成時に使用したツールチェーンは、swift.org の公式 Debian 13 x86_64 向け
配布物である Swift 6.4.0 RELEASE でした。ダウンロードした配布物の署名は、
公式 Swift 6.x 署名鍵で暗号学的に検証しました。GPG は、この鍵の有効期限が
9 月 14 日の署名後の 9 月 16 日に切れたことを報告しました。第三者のコンパイラー
配布物は使用しませんでした。このツールチェーンとダウンロードした配布物は、
リリースアーカイブに含みません。

最低バージョンの検証では、この Debian 13 ホスト上で公式 Swift 6.0.3 Ubuntu 24.04 も
使用しました。debug/release のビルドと全テストは、コンパイラー警告なしで成功しました。
両ツールチェーンの元のダウンロード物は、この配布物から除外しています。

最初の Apple 向け検証では、arm64 macOS 27.0 (26A428) 上で、ユーザーが既に使用していた
Command Line Tools 27.0.0.0.1787197235 を使用しました。構成は Apple Swift 6.4
(swiftlang-6.4.0.33.1, clang-2100.3.33.1)、macOS SDK 27.0 (26A5419a) でした。
この初期段階では、Xcode、SDK、ツールチェーンをインストールしませんでした。
独立した consumer は、同梱の Swift Testing 2078、Core Graphics、ImageIO、Vision を
使用しました。当初の XCTest の試行は、XCTest が存在しなかったため失敗しました。
これらの過去の結果は、`evidence/apple/README.md` と元のログに残しています。

ユーザーの明示的な承認後、同じ arm64 macOS 27.0 (26A428) ホストに公式 Xcode 27.0
(build 27A266a) をインストールし、保持しました。その後のツールチェーンは
Apple Swift 6.4 (swiftlang-6.4.0.34.1, clang-2100.3.34.1) で、macOS SDK 27.0
(26A425) と同梱の Swift Testing 2084 を使用しました。元のパッケージの debug/release
suite は、それぞれ XCTest の 54 メソッドと Swift Testing の 2 メソッドを実行し、
条件付きの Core Graphics/Vision テストを含め、失敗はありませんでした。Basic consumer の
release ビルドと実行は成功し、独立した consumer の 10 メソッドも両構成で再び成功しました。
ライブラリのソース変更は不要でした。

Xcode のデバイス SDK は、iOS 27.0 (24A430)、tvOS 27.0 (24J360)、watchOS 27.0 (24R360)
でした。8 つの debug/release ソースコンパイル構成はすべて成功しました。オブジェクトの
load command により、arm64 では最小 iOS 16 と tvOS 16、arm64_32 では最小 watchOS 9 を
確認しました。追加の watchOS arm64 構成は、watchOS 9 の triple を指定したにもかかわらず、
最小バージョンとして watchOS 26 を出力しました。これらは watchOS 9 の arm64 互換性を
証明するものではありません。これらの SDK 検証は、デバイスやシミュレーターでの
リンク、配置、署名、実行を示すものではありません。

別途実施したシミュレーター上での実行には、iOS 27.0 (24A434)、iPhone 17、arm64 を
使用しました。debug と release は、それぞれ XCTest の 54 メソッドと Swift Testing の
2 メソッドに成功し、失敗もスキップも 0 件でした。追加のテストソース変更は、
iOS シミュレーターで Vision revision 2 と対応する CPU デバイスを設定するものだけでした。
標準の SpecQR 画像と payload の完全一致の assertion は変更しませんでした。revision 2 は
非推奨ですが、このランタイムが対応する revision に含まれていました。ネイティブ macOS は
既定の request 構成を保持し、製品ライブラリのソースも変更しませんでした。

既定の revision 4 は当初、Vision Code 9 のエラー "Could not create inference
context." を返しました。
An independent 40-request simulator probe compared default/enlarged
SpecQR images against Apple's CoreImage-generated QR control: revisions 3/4
returned no observations for both generators, while revision 1 and revision 2
with CPU recovered the payload.
調査では、完全一致が 19 件、空の結果が 20 件、推論エラーが
1 件記録されました。診断プロセスの exit 0 は、全ケースの成功を意味しません。
この結果が示したのは、その時点のシミュレーターの制限であり、SpecQR の描画器の不具合や
既定 revision での検証成功を確認したものではありません。証拠一式は
`evidence/xcode/vision-probe/README.txt` にあります。テスト専用の分岐は、先行する Linux の
再実行で検証した実行時ソースを変更しません。後続の証拠と残る検証条件は、
`evidence/xcode/README.md` と `evidence/xcode/sdk/README.txt` を参照してください。
