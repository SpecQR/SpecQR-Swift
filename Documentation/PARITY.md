# Feature parity acceptance checklist

基準: SpecQR JavaScript `3.0.0-rc.2`、固定 commit
`15ad15e5c770ea0e39072f8f88b2733018f02ffd`（2026-08-02）。
基準となるソース: https://github.com/SpecQR/SpecQR/tree/15ad15e5c770ea0e39072f8f88b2733018f02ffd

高レベル API での literal-percent の正しさに関する差分は COMPATIBILITY.md に記録しています。
この Swift 実装は新たに作成しました。以前に作成された Swift archive は、
この環境で実ファイルとして取得できず、ソースとして使用していません。
この一覧は受入条件を記録します。チェック済みとするには、実行した証拠が必要です。

- [x] package/runtime の依存なしで Swift Package の debug と release を build
- [x] Model 2 の version 1–40、level L/M/Q/H、mask 0–7 と最小 penalty の自動選択
- [x] numeric、alphanumeric、UTF-8 byte、raw binary、決定的な Kanji、混在・手動 segment
- [x] 自動 segment 分割、count-field の境界、厳密な version/range option、ECC boost
- [x] ECI、FNC1 first/second、Structured Append の低レベル control と順序・競合の検証
- [x] matrix を構築しない planning、overflow を含む見積り、容量の照会
- [x] 生成時の diagnostics、容量、segment、mask score、描画・scan の警告
- [x] GS1 AI dictionary、human-readable/raw parser、validator、GTIN/SSCC check digit
- [x] GS1 Digital Link の作成・解析・検証・正規化
- [x] Structured Append の text/binary/manual 分割、canonical parity、再結合の検証、diagnostics
- [x] matrix、SVG、PNG、data URL、移植可能な RGBA と、overflow に対して安全な描画上限
- [x] Swift platform adapter と条件付きテストを用意し、未実行の状態を開示
- [ ] Apple SDK/platform の実行 gate（Apple 環境が必要）
- [x] 実際の source に基づき、mode、version、ECC、mask にまたがる差分検証 fixture
- [x] 独立した QR decoder/reference による検証
- [x] 異常ケース、境界、大きな入力、並行処理、変更不能な結果の安全性
- [x] CLI、example、API 文書、license/provenance、未公開の release checklist
- [x] 独立した統合 code review に対応し、archive とともに配布用 checksum を提供
- [x] repository 作成、push、PR、tag、release、package 公開は未実施
