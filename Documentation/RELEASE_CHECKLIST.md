# リリースチェックリスト

ソース repository は [SpecQR/SpecQR-Swift](https://github.com/SpecQR/SpecQR-Swift) です。
初回のソース公開は `main` branch を対象とし、安定版の version tag / GitHub Release は
まだありません。以下は公開 commit の確認と、今後の versioned release のチェック項目です。

1. [VERIFICATION.md](VERIFICATION.md) の実行済み・未実施を確認する。
2. macOS で `swift test` / `swift test -c release` を実行し、Core Graphics adapter と
   Apple Vision decoder tests を通す。iOS/tvOS/watchOS は実際の SDK で build する。
   Xcode 27.0 で元の suite は debug/release 各 54 XCTest +2 Swift Testing、失敗 0 で完了。
   独立 10 tests も Xcode で debug/release 再実行成功。実 SDK による 8 compile-only lanes も完了し、
   iOS 16/tvOS 16/arm64_32 watchOS 9 の minimum を object で確認した。追加の watchOS arm64 lane は
   emitted minimum が 26 のため watchOS 9 の証拠とは扱わない。iOS 27.0 /24A434、iPhone 17 arm64
   simulator でも debug/release 各 54 XCTest +2 Swift Testing、失敗 0・skip 0 で完了。
   Vision は simulator 分岐で revision 2 + 対応 CPU を選択した結果であり、default revision 4 の成功ではない。
   revision 3/4 が SpecQR と Apple CoreImage 対照画像の両方で decode 不成立だった制限を
   [Vision probe](evidence/xcode/vision-probe/README.txt) と合わせて確認する。
   [Xcode evidence](evidence/xcode/README.md) と [SDK 詳細](evidence/xcode/sdk/README.txt) を確認する。
   SDK compile 結果は device での link/deploy/signing/実行や minimum OS 実行の完了を意味しない。
3. 最低 Swift 6.0 でも `Scripts/verify-all.sh` を実行する。
4. `git diff --check`、ライセンス、public API、再現性、archive SHA-256 を確認する。
5. 公開した exact commit の [GitHub Actions](https://github.com/SpecQR/SpecQR-Swift/actions) を確認する。
   保存済みのローカル検証を remote CI 成功として扱わない。このチェックリスト自体も CI 成功を宣言しない。
6. versioned release では version/tag、API 互換性方針、release notes を確定し、その exact commit の
   必要な検証を確認してから tag と GitHub Release を作成する。`main` のソース公開とは区別する。
7. 未実施の hardware/scanner validation を「実施済み」と表現しない。

印刷条件、端末 camera、scanner の metadata 対応、読み取り性能はこの package の
unit tests だけでは保証できません。GS1 認証や規格適合認証も別途必要です。
