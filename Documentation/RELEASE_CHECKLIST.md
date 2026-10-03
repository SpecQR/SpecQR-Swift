# リリースチェックリスト

ソース repository は [SpecQR/SpecQR-Swift](https://github.com/SpecQR/SpecQR-Swift) です。
初回のソース公開は `main` branch を対象とし、安定版の version tag / GitHub Release は
まだありません。以下は公開 commit の確認と、今後の versioned release のチェック項目です。

1. [VERIFICATION.md](VERIFICATION.md) の実行済み・未実施を確認する。
2. macOS で `swift test` / `swift test -c release` を実行し、Core Graphics adapter と
   Apple Vision decoder tests を通す。iOS/tvOS/watchOS は実際の SDK で build する。
   Xcode27.0で元のsuiteはdebug/release各54 XCTest +2 Swift Testing、失敗0で完了。
   独立10 testsもXcodeでdebug/release再実行成功。実SDKによる8 compile-only lanesも完了し、
   iOS16/tvOS16/arm64_32 watchOS9のminimumをobjectで確認した。追加のwatchOS arm64 laneは
   emitted minimumが26のためwatchOS9の証拠とは扱わない。iOS27.0 /24A434、iPhone17 arm64
   simulatorでもdebug/release各54 XCTest +2 Swift Testing、失敗0・skip0で完了。
   Visionはsimulator分岐でrevision2 + 対応CPUを選択した結果であり、default revision4の成功ではない。
   revision3/4がSpecQRとApple CoreImage対照画像の両方でdecode不成立だった制限を
   [Vision probe](evidence/xcode/vision-probe/README.txt)と合わせて確認する。
   [Xcode evidence](evidence/xcode/README.md)と[SDK詳細](evidence/xcode/sdk/README.txt)を確認する。
   SDK compile結果はdeviceでのlink/deploy/signing/実行やminimum OS実行の完了を意味しない。
3. 最低 Swift 6.0 でも `Scripts/verify-all.sh` を実行する。
4. `git diff --check`、ライセンス、public API、再現性、archive SHA-256 を確認する。
5. 公開した exact commit の [GitHub Actions](https://github.com/SpecQR/SpecQR-Swift/actions) を確認する。
   保存済みのローカル検証を remote CI 成功として扱わない。このチェックリスト自体も CI 成功を宣言しない。
6. versioned release では version/tag、API互換性方針、release notesを確定し、そのexact commitの
   必要な検証を確認してからtagとGitHub Releaseを作成する。`main`のソース公開とは区別する。
7. 未実施の hardware/scanner validation を「実施済み」と表現しない。

印刷条件、端末 camera、scanner の metadata 対応、読み取り性能はこの package の
unit tests だけでは保証できません。GS1 認証や規格適合認証も別途必要です。
