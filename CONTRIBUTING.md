# Contributing

claude-codex-audit-toolkit へのコントリビューションを歓迎します。

## 現在の version と成熟度

- **v0.4-beta (自己監査凍結)**: 5dmgmt 内部で 3 ケース実証済 (Workshop 4R / SIFT 13R / video-subtitler 5R)。本リポ自己監査は **R5 で凍結** ([`examples/self-audit-history.md`](examples/self-audit-history.md))。旧 10 ファイル R1=62 → R5=51 で同一範囲下降傾向は維持確認済、構造バグ・実用ガードは R5 時点の P1 反映で解消、残 P1 (説明追加要求系) は [`docs/_review-notes-v0.4-beta-frozen.md`](docs/_review-notes-v0.4-beta-frozen.md) に転記。
- **凍結理由**: 自己内ループだけで refine しても外部汎化価値が増えない / 残 P1 は「R5 時点の状態を docs に転記しろ」型の修正の負債化パターン。
- **N=1 仮説の制約**: モデル選択 (gpt-5.5 vs gpt-5.4)・Fix 6 (横断 6 観点)・adapter 汎化は現時点で N=各 1-2 ケースの観察仮説です。外部事例の追加では「観察値 / 仮説 / 汎化主張」を分けて記録してください。
- v1.0 への到達条件: 5dmgmt 系列以外の事例 1+ 件、`docs/_review-notes-v0.4-beta-frozen.md` の各項目を外部事例の知見を踏まえて再判定、英訳 README。次の自己監査 (R6) は外部事例で軸が変わってから。

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

既存 adapter は **Fix 2 (Web UI / DOM 検証)、Fix 5 (Next.js dotenv)、docs/05 #5 (Node.js)、docs/05 #7/#8/#9 (Next.js)、docs/06 (Next.js + 自前 auth)** です (詳細は [docs/05 §適用範囲表](docs/05-env-lint-checklist.md) を正本とする)。新しい adapter (例: Rails / Django / Supabase Auth / NextAuth / Python pipeline 等) を追加するには:

- `docs/adapters/<framework>.md` を新設 (`docs/adapters/_template.md` のひな形は近日整備予定 / それまでは既存 docs/06 の構造を参考に: 適用範囲明示 / コアとの差分 / docs/05 項目との対応 / N/A 項目 / 検証 example / N= 注記)
- README の adapter 一覧と docs/05 §適用範囲表に追加
- 該当 example で adapter 適用例を示す
- PR description で docs/05 正本表との対応 (どの項目が該当 / 非該当 / 新規追加か) を明示

### 3. Bug 報告 / 構造的問題の指摘

ツールキット自身が「ALL PASS する状態」にはまだ達していません。特に scripts や docs の矛盾、汎用と限定の境界の曖昧さ等、構造的な指摘は歓迎します。

## 開発フロー

1. Issue を立てて方針議論 (大きな変更の場合)
2. branch 名: `feat/<topic>` / `fix/<topic>` / `docs/<topic>`
3. PR description に「適用範囲」(全体 / コア / adapter / example) を明示
4. 自己監査ループを 1 周回してから PR (本ツールキットを使ってください):
   - **ランブック監査の場合**: README Quick Start 1-4 を実行、結果リンクまたは件数推移を PR description に添付
   - **コードベース監査の場合**: [`docs/07-runbook-templates/code-audit-runbook.md`](docs/07-runbook-templates/code-audit-runbook.md) の Step 0-3 を実行、AUDIT_RUNBOOK.md + `--skip-git-repo-check` 必須

## ライセンス

[MIT License](LICENSE)。コントリビュートされたコードは MIT で取り込まれます。

## 質問 / 議論

- GitHub Issues (大規模議論も当面は Issues に集約)
