# Changelog

## Initial public source — 2026-10-03

[SpecQR/SpecQR-Swift](https://github.com/SpecQR/SpecQR-Swift) の `main` branch で提供する
初回ソースです。安定版の version tag / GitHub Release はまだありません。
互換参照元の JavaScript `3.0.0-rc.2` は Swift package の version ではありません。

- Model 2 encoder、ECI/FNC1、Kanji、最適化、planning、diagnostics を Swift で新規実装
- GS1 の 50 AI、Digital Link、Structured Append、SVG/PNG/RGBA/portable canvas を追加
- Swift 6 strict-concurrency / Sendable 対応、runtime package dependencies はゼロ
- pinned JS、Nayuki、jsQR、ZXing Java/C++ による差分・独立 decode 検証を追加
- high-level FNC1 raw text の literal `%` を byte mode で保護する安全な差分を採用
- Apple Core Graphics / Vision tests と CI workflow を追加
- macOS上で独立Swift Testing、Core Graphics / ImageIO / Visionのdebug/release実行証跡を追加
- Basic consumerにmacOS13 minimumを明示し、render上限比較の32-bit Int literal overflowを修正
- Xcodeで元のmacOS suite、iOS/tvOS/watchOSの8 SDK compile lanes、iOS27.0 simulatorのdebug/release検証を実施
- iOS simulatorのVision testに対応revision2 + CPU構成を追加。default revisionの制限とApple CoreImage対照probeを記録

ローカル実行証跡と未実施項目は [検証結果](Documentation/VERIFICATION.md)、
公開 commit の CI 状態は [GitHub Actions](https://github.com/SpecQR/SpecQR-Swift/actions)を参照してください。
この記録は CI 成功や stable release の宣言ではありません。
