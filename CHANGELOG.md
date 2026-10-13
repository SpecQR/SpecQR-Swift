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
- macOS 上で独立 Swift Testing、Core Graphics / ImageIO / Vision の debug/release 実行証跡を追加
- Basic consumer に macOS 13 minimum を明示し、render 上限比較の 32-bit Int literal overflow を修正
- Xcode で元の macOS suite、iOS/tvOS/watchOS の 8 SDK compile lanes、iOS 27.0 simulator の debug/release 検証を実施
- iOS simulator の Vision test に対応 revision 2 + CPU 構成を追加。default revision の制限と Apple CoreImage 対照 probe を記録

ローカル実行証跡と未実施項目は [検証結果](Documentation/VERIFICATION.md)、
公開 commit の CI 状態は [GitHub Actions](https://github.com/SpecQR/SpecQR-Swift/actions) を参照してください。
この記録は CI 成功や stable release の宣言ではありません。
