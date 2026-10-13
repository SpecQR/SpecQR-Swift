# Independent macOS consumer validation

This Swift Testing package depends on the root `SpecQR` library by a local path
and uses public APIs only.

この Swift Testing package は、ローカルパスでルートの `SpecQR` library に依存し、
公開 API だけを使用します。Core Graphics、ImageIO、Vision は無条件に import します。
必要な framework がなければ build は失敗し、テストを skip して成功と報告することはありません。
外部依存はインストールしません。

repository のルートから実行します。

```sh
./Scripts/verify-apple.sh
# Or one configuration:
./Scripts/verify-apple.sh release
```

consumer tests は、straight RGBA の provider bytes、Core Graphics の画像 metadata と
storage lifetime、ImageIO による実際の PNG decode、CGImage と PNG の両方からの
Vision decode、UTF-8 と GS1 の literal percent / group separator の保持、
不正な描画と resource limits、FNC1 の両形式、Structured Append の headers・順序を
入れ替えた merge・parity 不一致の拒否、並行描画を検証します。
2 つの corpus tests は、元のルートの test resources から直接、GS1 の全 1,411 fixtures と
Structured Append の全 22 fixtures を再実行します。

script は、一部の CLT release で省略されるインストール済み Testing macro と runtime の
パスを補い、2 つの build jobs を使い、cache を `.build` 配下に保持します。任意指定の
`SPECQR_APPLE_BUILD_DIR` と `SPECQR_APPLE_CACHE_DIR` で保存先の絶対パスを設定できます。
独立 test runner は、インストール済みの Testing framework の要件に従い macOS 14 を
対象にします。library と Basic consumer の対象は引き続き macOS 13 です。

これは macOS の追加証拠です。元の XCTest test suite を実行したり、置き換えたりするものでは
ありません。Apple の Command Line Tools では、compiler、macOS SDK、Swift Testing が
使えても XCTest がない場合があります。その場合、元の suite は実行できない状態として
記録してください。この package は独立した consumer lane です。

この package の結果は、iOS/tvOS/watchOS の SDK や simulator での実行、deployment minimum での
実行時の挙動、実機 camera による読み取り、印刷品質、barcode 規格の認証を証明しません。
ローカルの decoder がテスト対象の payload を保持できなければ、Vision の期待値検証は
明示的に失敗します。assertion を黙って省略せず、その制限を調査して記録してください。
