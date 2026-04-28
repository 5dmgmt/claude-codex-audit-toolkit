# Contributing

claude-codex-audit-toolkit へのコントリビューションを歓迎します。

## 現在の version と成熟度

- **v0.4-beta**: 5dmgmt 内部で 3 ケース実証済 (Workshop 4R / SIFT 13R / video-subtitler 5R) ですが、**コア (フレームワーク中立部分)** と **adapter (Next.js / Python pipeline 等)** の境界が再編成された直後です。利用者からのフィードバックを募集中。
- v1.0 への到達条件: 5dmgmt 系列以外の事例 1+ 件、コア部分の自己監査 R3 ALL PASS、英訳 README。

## 特に価値があるコントリビューション

### 1. 新規 example の追加 (5dmgmt 系列以外)

`examples/` に自分のプロジェクトでツールキットを使った経験を追加してください。**フレームワークが Next.js + 自前 auth 以外** の事例 (Rails / Django / Go / Rust / Python pipeline 等) は特に価値が高いです。

ひな形: 既存 `examples/workshop-course1-snippet.md` / `sift-phase-c-snippet.md` / `video-subtitler-snippet.md` を参考に。

含めてほしい情報:
- 監査対象のスコープと言語 / フレームワーク
- 各ラウンド / 周の検出件数推移 (概数で可)
- 五月雨防止 4 行ブロックや Fix 1-6 の効果 / 不在の影響
- 該当 / 非該当の Fix の判定 (例: 「Fix 5 dotenv は Rails では適用外」)
- 教訓 / 反省

### 2. Adapter の新規追加

Fix 5 (Next.js dotenv) や docs/06 (Next.js + 自前 auth) は **adapter** として位置付けられています。新しい adapter (例: Rails / Django / Supabase Auth / NextAuth) を追加するには:

- `docs/adapters/<framework>.md` を新設
- README の adapter 一覧に追加
- 該当 example で adapter 適用例を示す

### 3. Bug 報告 / 構造的問題の指摘

ツールキット自身が「ALL PASS する状態」にはまだ達していません。特に scripts や docs の矛盾、汎用と限定の境界の曖昧さ等、構造的な指摘は歓迎します。

## 開発フロー

1. Issue を立てて方針議論 (大きな変更の場合)
2. branch 名: `feat/<topic>` / `fix/<topic>` / `docs/<topic>`
3. PR description に「適用範囲」(全体 / コア / adapter / example) を明示
4. 自己監査ループを 1 周回してから PR (本ツールキットを使ってください)

## ライセンス

[MIT License](LICENSE)。コントリビュートされたコードは MIT で取り込まれます。

## 質問 / 議論

- GitHub Issues
- 大規模議論は GitHub Discussions (近日開設予定)
