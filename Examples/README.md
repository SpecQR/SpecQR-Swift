# 実行例

```sh
swift run --package-path Examples/Basic -c release
```

public product `SpecQR` だけを import する独立 Swift Package consumer です。
URL、binary Data、literal `%` を含む GS1、Digital Link、Structured Append、
matrix-free diagnostics を実際に実行します。出力ファイルが必要な場合は CLI を使います。

```sh
swift run specqr-cli 'HELLO WORLD' > qr.svg
swift run specqr-cli --png qr.png 'HELLO WORLD'
```
