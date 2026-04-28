# Contributing

claude-codex-audit-toolkit へのコントリビューションを歓迎します。

## 現在の version と成熟度

- **v0.5-nextjs-supabase (Next.js + Supabase 特化)**: 5dmgmt 内部で 3 ケース実証 (Workshop 4R / SIFT 13R / video-subtitler 5R)。Workshop / SIFT は Next.js + Supabase / video-subtitler は Whisper+ffmpeg pipeline (Next.js + Supabase 範囲外のコードベース監査応用例として残置)。自己監査は **R6 で凍結** ([`examples/self-audit-history.md`](examples/self-audit-history.md))、旧 10 ファイル R1=62 → R6=33 (-47%) で同一監査単位下降傾向維持、構造バグは [`docs/_review-notes-v0.4-beta-frozen.md`](docs/_review-notes-v0.4-beta-frozen.md) の凍結項目以外を反映済。
- **特化方針**: 「フレームワーク中立な汎用ツールキット」を目指す代わりに **Next.js + Supabase に絞って solid に仕上げる** 方針。AIFCC Workshop の cohort で教材化して同条件で検証を積み上げ、外部事例の躓きポイントを最小化する。Rails / Django / Go 等の対応は v1.0 以降の判断。
- **N=1 仮説の制約**: モデル選択 (gpt-5.5 vs gpt-5.4)・Fix 6 (横断 6 観点) は現時点で N=各 1-2 ケースの観察仮説です。外部事例の追加では「観察値 / 仮説 / 汎化主張」を分けて記録してください。
- **AIFCC Workshop での現状**: Course 1 PART 105 / Phase 10503 (最終 Phase「イテレーション → 公開 → 次のステップ」) に **任意オプションとして組込み済** (リポリンク + 五月雨防止プロンプト v2 + `codex-audit-prompt.txt` 取得手順)。位置づけは「Course 1 卒業段階では任意 / 本格的な品質管理が必要になったタイミングで導入」。
- v1.0 への到達条件: (1) 5dmgmt 系列以外の **Next.js + Supabase** 事例 1+ 件、(2) AIFCC Workshop での **本格教材化** (現状の任意オプション → 必修 Phase or PART 化、cohort 検証 1 周)、(3) Supabase Auth + RLS adapter 整備 (`docs/06-supabase-auth.md` 新設想定)、(4) `docs/_review-notes-v0.4-beta-frozen.md` の凍結項目を外部事例の知見で再判定して P1 残ゼロ、(5) 自己監査 / 追加事例で **同一監査単位 + 同一軸換算の下降傾向** 維持、(6) 英訳 README。次の自己監査 (R7) は外部事例または Supabase Auth adapter 追加で軸が変わってから。

## 特に価値があるコントリビューション

### 1. 新規 example の追加 (5dmgmt 系列以外の Next.js + Supabase プロジェクト)

`examples/` に自分の **Next.js + Supabase プロジェクト** でツールキットを使った経験を追加してください。Supabase Auth / NextAuth / Auth0 / Clerk 等の auth pattern 違いの事例も歓迎です。

ひな形: 既存 `examples/workshop-course1-snippet.md` / `sift-phase-c-snippet.md` を参考に。

含めてほしい情報:
- 監査対象のスコープ (ランブック / コードベース / Phase 数 / 行数)
- Next.js バージョン + auth pattern (自前 / Supabase Auth / NextAuth 等) + Supabase 利用範囲 (DB / Auth / Storage / Realtime)
- 各ラウンド / 周の検出件数推移 (概数で可)
- 五月雨防止 4 行ブロックや Fix 1-6 の効果 / 不在の影響
- docs/05 14 項目のうち該当 / N/A 判定 (auth pattern によって docs/06 の適用差が出る)
- 教訓 / 反省

### 2. Auth pattern adapter の追加 (Next.js 内)

既存の dev bypass 4 原則は **Next.js + 自前 auth** 前提 (`docs/06-dev-bypass-design.md`)。Next.js 内で別 auth pattern (Supabase Auth + RLS / NextAuth / Auth0 / Clerk 等) の adapter を追加する PR は v1.0 への到達条件 (3) に直結します:

- `docs/06-<auth-pattern>.md` を新設 (例: `docs/06-supabase-auth.md` / `docs/06-nextauth.md`)
- 既存 `docs/06` 4 原則のうち、auth pattern で変わる部分・共通部分を明示
- session check の差 (cookie / JWT / RLS との連携) を実装パターンで示す
- write 防御の negative test (auth pattern 別) と admin server-side RBAC の証跡を含める
- README の adapter 一覧と docs/05 §適用範囲表に追加

### 3. 対象外 framework (Rails / Django / Go / Python pipeline 等)

v0.5-nextjs-supabase の段階では **Next.js + Supabase 以外への展開は scope 外** とし、Next.js + Supabase 内の実証を優先します。他 framework の事例 / adapter contribution は v1.0 以降の判断とします。それまでは fork して各自で運用する形を推奨。

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
