# Independent decoder verification

These are test-only adapters.

これらはテスト専用の adapters です。JavaScript SpecQR の oracle は import せず、
第三者の decoder やダウンロードした binary を Swift product にリンクしません。

## Run

Swift、Node 20+、`curl`、compiler module を含む Java 17+、pip が利用できる Python 3.10+ を
用意し、package のルートから実行します。

```sh
swift build -c release
export SPECQR_CLI="$(swift build -c release --show-bin-path)/specqr-cli"
node Scripts/verify-zxing.mjs
python3 Scripts/verify-zxing-cpp.py
```

scripts は初回利用時に固定したテスト用依存を取得します。ネットワーク制限のある
CI runner では Maven Central と PyPI へのアクセスを許可する必要があります。
以降の実行では `.build/` を再利用します。C++ harness は意図的に公開済み wheel を必須とし、
native dependency を黙って build しません。lock file は公開済みの 3.1.1 wheels 全 30 件の
ハッシュを含み、未対応の interpreter/platform では明示的に失敗します。

### Java suite

- 公式 Maven Central repository の ZXing `core` 3.5.4
- SHA-256: `71de5d89341b5fcf5dd89da7f44e84d825d0e084cdf3ec77c9abe26b0f0ceb13`
- [Upstream](https://github.com/zxing/zxing), Apache-2.0
- [Pinned artifact](https://repo.maven.apache.org/maven2/com/google/zxing/core/3.5.4/core-3.5.4.jar)

`DecodeSymbols.java` は Java source-file launch で実行するため、別途 `javac` executable や
Maven をインストールする必要はありません。直接渡した matrices は ZXing の QR decoder で
処理します。実際の Swift renderer が生成した PNG は、Java ImageIO、ZXing の輝度変換、
binarizer、finder-pattern detection、QR reader を通します。
`PURE_BARCODE` は意図的に有効化していません。

suite は、全 ECC levels と masks、numeric/alphanumeric/Kanji/UTF-8 payloads、
binary byte segments、ECI 3/20/26/170、FNC1 first-position symbology、Structured Append の
合法な `(index,total)` の全 135 組合せ、高レベル Swift API が生成した 6 sets を検証します。
これらの sets は 48 symbols を含み、numeric、alphanumeric、Unicode scalar の境界、
全 256 byte 値、16-symbol set、manual mixed modes を対象とします。独立 decode で得た
sequence/parity metadata を使い、読み取り順序が異なる状況を模して各 set を再結合します。

decode が成功した場合は、誤り訂正後の data-codeword stream 全体を Swift が生成したものと
比較します。制御した破損テストでは、すべての ECC/mask の組合せに対し、Version 1 の異なる
3 つの data codewords の各 1 module を反転します。suite は復元した data と、ZXing が示す
誤り訂正数が正確に 3 であることの両方を確認します。全白の不正な matrix は拒否される必要があります。

ZXing Java 3.5.4 の FNC1-second branch は application indicator を消費しません。
これは decoder の制限であり、この suite は FNC1-second を検証したとは**主張しません**。
C++ suite で別途検証します。

### C++ suite

- ZXing-C++ 3.1.1。正確な release と wheel の SHA-256 hashes は次に記録
  `zxing-cpp-requirements.txt`
- [Upstream](https://github.com/zxing-cpp/zxing-cpp), Apache-2.0
- [Release metadata](https://pypi.org/pypi/zxing-cpp/3.1.1/json)

script は wheels を `.build/zxing-cpp` だけにインストールします。pip の
`--require-hashes`、`--only-binary=:all:`、`--no-deps` を使います。Python の native memoryview を
使うため、Pillow も NumPy も必要ありません。

合法な FNC1-second indicators 全 152 通り (00–99, A–Z, a–z)、明示的な control segments と
high-level options、alphanumeric/FNC1 escapes、正確な binary bytes、全 ECC levels と
全 masks を対象とします。ZXing-C++ は application indicator を decoded bytes の prefix として
返し、assertions はその prefix を明示的に含めます。別の regression tests で、高レベル API の
literal percent の保持、二重 percent、実際の U+001D separators、segment optimization 無効を
確認します。明示的な低レベル FNC1 alphanumeric segments では、引き続き標準の
単一 percent を separator、二重 percent を literal とする規則を使います。

## Outputs and limits

reports、decoded records、PNG fixtures、依存する jars/wheels、コンパイル済み helpers は、
Git の追跡対象外である `.build/zxing-java` と `.build/zxing-cpp` 配下に保持します。
ソース配布から `.build/` を除外してください。reports は、検証した Swift executable の
SHA-256、依存の識別情報、検証件数、明示的な制限を含みます。

これらは実際の独立 decoder tests ですが、合成した画像や matrix のテストは、実機 camera や
印刷の試験、ISO/GS1 の正式な適合認証に代わるものではありません。任意の ECI labels、
あらゆる damage pattern、未対応の decoder metadata は対象外です。
