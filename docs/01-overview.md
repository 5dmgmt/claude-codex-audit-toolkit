# 01. Claude Code + Codex 監査ループの全体像

> **Version**: v0.5-nextjs-supabase — **Next.js + Supabase 特化**。5dmgmt 内部で 3 ケース実証 (Workshop 4R / SIFT 13R / video-subtitler 5R)。AIFCC Workshop 教材組込み準備中、5dmgmt 系列以外の Next.js + Supabase 事例を募集中 ([CONTRIBUTING.md](../CONTRIBUTING.md))。

## 想定読者

- **Next.js + Supabase プロジェクト** を Claude Code (Anthropic) で書いている人
- 書いた成果物 (ランブック・教材・実装コード) を OpenAI Codex CLI (`codex exec` / `codex review`) で品質監査したい人
- 「ラウンドごとに finding が小出しに出続けて終わらない」「3 ラウンド超えるべきか scope cut すべきか判断できない」と悩んでいる人

> Rails / Django / Go / Python pipeline 等は v0.5 段階では scope 外。fork して各自運用を推奨します ([CONTRIBUTING.md](../CONTRIBUTING.md) §3 対象外 framework)。

## 本ツールキットの 3 つの柱

```
[1. 五月雨防止プロンプト v2 (実走証拠ベース)]
   ↓ 監査単位 + 4 行ブロック + 過去反映済リスト 30+ 蓄積
[2. 6 つの決定的対策 (5 fixes + 横断 6 観点 ULTRATHINK)]
   ↓ ランブック品質 / コード品質の再現性・決定性を高め、ALL PASS または妥当な scope cut まで持っていく
[3. 収束判定基準]
   → 正常収束 (継続) vs scope creep (停止) を識別
```

> 旧 v2 (deprecated) で推奨していた「7 要素重圧テンプレ (全行 enumerate / mandatory セクション / 3 段階構造 / 全カテゴリ均等深さ含む)」は Codex CLI 0.125.0 で tool ループに陥ることが判明したため廃止しました。詳細は [`08-known-pitfalls.md`](08-known-pitfalls.md) 参照。

## docs マップ — どこを読むか

利用者の状況によって読むべき場所が変わります (docs/05 §適用範囲表を正本とする):

| 状況 | 必読 (コア) | 状況に応じた adapter |
|---|---|---|
| ランブック (静的文書 / 教材 / 仕様書) を Codex で監査したい | docs/02 / docs/03 Fix 1, 3, 4 / docs/04 / [docs/07-runbook-templates/manual-audit-runbook.md](07-runbook-templates/manual-audit-runbook.md) | docs/05 コア中立項目 (#1/#2/#3/#4/#6/#10/#11/#13/#14) + #12 (Codex CLI 利用者全員) |
| コードベース (Whisper pipeline / アプリ実装等) を Codex で監査したい | docs/02 / docs/03 Fix 1, 3, 4, **6** / docs/04 / [docs/07-runbook-templates/code-audit-runbook.md](07-runbook-templates/code-audit-runbook.md) | docs/05 同上 + Web UI 検証あれば docs/03 Fix 2 |
| Next.js プロジェクトの実装監査 | 上記コードベース監査 | docs/03 Fix 5 (Next.js dotenv adapter) + docs/05 #5 (Node.js adapter) + #7/#8/#9 (Next.js adapter) + docs/06 (Next.js + 自前 auth adapter) |
| Next.js + 自前 auth プロジェクト | 上記コードベース監査 | docs/06 (dev bypass 4 原則) |
| Next.js + Supabase Auth + RLS プロジェクト | 上記コードベース監査 | docs/06 の自前 auth 4 原則の一部は転用可。Supabase Auth + RLS adapter は v1.0 で `docs/06-supabase-auth.md` 新設予定 (現状は自前 auth として読み替え + Supabase Auth helpers の session check + RLS policy 検査を別途) |
| ツールキット内部仕組みを理解したい | docs/01-08 全部 | examples/ 全部 |

**共通 (Next.js + Supabase 全体 / Codex CLI 利用者全員)**:
- docs/02 (五月雨防止) / docs/03 Fix 1, 3, 4, 6 / docs/04 (収束判定) / docs/07-runbook-templates/ テンプレ自体
- docs/05 共通 = #1/#2/#3/#4/#6/#10/#11/#13/#14 / 共通 (Codex CLI 固有) = #12

**パターン (Next.js + Supabase 内の使い分け)**:
- docs/03 Fix 2 (Web UI / DOM 検証 / Playwright 等)
- docs/03 Fix 5 + docs/05 #5/#7/#8/#9 (Next.js dotenv / npm port pin / next-env.d.ts / .env.local)
- docs/06 (Next.js + 自前 auth)
- (v1.0 予定) docs/06-supabase-auth.md (Supabase Auth + RLS) / docs/06-nextauth.md / docs/06-clerk.md 等

## 監査の 2 系統 (ランブック監査 / コードベース監査)

監査対象によって運用パターンが大きく異なります。本ツールキットは両系統をカバーします:

| 系統 | 監査対象 | 1 ラウンドの単位 | 推奨 model | 重点となる事前準備 | 代表例 |
|---|---|---|---|---|---|
| **ランブック監査** | 静的文書 (教材 / 監査ランブック / 仕様書) | **1 ファイル** (`docs/foo.md`) | `gpt-5.5 xhigh` | 環境系 lint 14 項目撲滅 ([`docs/05`](05-env-lint-checklist.md)) | Workshop 4R / SIFT 13R |
| **コードベース監査** | 実装コード (パイプライン / アプリ全体 / 大規模 codebase) | **1 commit** (リポ全体 / 複数ファイル) | `gpt-5.4 xhigh` (video-subtitler 1 ケースで `gpt-5.5 xhigh` の 19 分超 hang を観測 / 根本原因未特定) | 横断 6 観点 ULTRATHINK ([`docs/03 Fix 6`](03-five-decisive-fixes.md#fix-6-反復監査の-1-周目で横断-6-観点-ultrathink-を全部洗う)) | video-subtitler 5R |

> **モデル選択は N=各 1-2 ケースから抽出した仮説**。コードベース監査の `gpt-5.5 xhigh` hang は video-subtitler 1 例での観察で根本原因未特定。他 framework / 他コードベースでの汎化は要検証。

### コードベース監査のための追加運用

- `--skip-git-repo-check` 必須 (git 状態で Codex の挙動が変わるのを避ける)
- 出力サイズが 100 KB+ になる場合がある (`--output-last-message` ファイルから tail で取得)
- 1 周ごとに push せず、修正をまとめて 1 commit で push (closure 成果物の散逸を防ぐ)
- ランブック (`AUDIT_RUNBOOK.md` 等) を repo 内に置いて毎周 Codex に渡す再開手順を確立する

## 役割分担

| ツール | 役割 |
|---|---|
| **Claude Code** | ランブック・教材・ドキュメントの起案・修正・編集 |
| **Codex CLI** | 独立した第三者視点でランブック品質を監査 (gpt-5.5 + xhigh) |
| **本ツールキット** | 両者の連携を「五月雨」させずに安定収束させる運用パターン |

## 典型的なフロー

```
1. Claude Code でランブック draft v1 を書く
   ↓
2. 環境系 lint チェックリスト (14 項目 / docs/05) で事前撲滅
   ↓
3. Codex で R1 監査 (五月雨防止プロンプト v2 / docs/02 を冒頭配置)
   ↓
4. R1 finding 反映 → ランブック v2
   ↓
5. Codex で R2 監査 (R1 反映を pre-condition として受け入れる)
   ↓
6. ラウンドごとの finding 件数 + 4 条件 (下降傾向 / 矛盾指摘なし / 同一 finding 再発なし / 未解決 finding が具体行に紐づく) を docs/04 で評価
   - 全条件 ✅ → 正常収束として継続
   - 2 ラウンド連続停滞 / 注記なき矛盾 / 同一 finding 再発 / 未解決 finding が具体行に紐づかない or 抽象的 finding 増加 → scope creep として scope cut 検討
   ↓
7. ALL PASS or scope cut として確定
```

## 期待される結果

このツールキットを適用すると、**短いラウンド数で PASS または妥当な scope cut の確定に到達しやすくなる** という仮説に基づいて運用しています (具体的なラウンド数は対象により大きく異なる)。

明示できる実走実証は次の 3 ケース:
- SIFT Phase C ランブック: **13 ラウンド** で ALL PASS (ランブック監査)
- Workshop Course 1 ランブック: **4 ラウンド** で scope cut (ランブック監査)
- video-subtitler コードパイプライン: **5 周** で High/Medium/Low 下降収束 (コードベース監査 / 残課題 2 件は次セッション判断)

逆に、これらを適用しないと **数ラウンド以上停滞しうる** 典型症状:
- 同じ指摘が周回する
- 過去ラウンドで反映済の修正を Codex が再指摘してくる
- 矛盾する指摘 (R6 で「A にすべき」→ R8 で「B にすべき」) が出る

主因は **Codex 本体の良否ではなく、プロンプト設計・ランブック構造・監査基盤の決定性不足** にあります。

## 次に読むべき文書

1. [`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) — 五月雨防止プロンプト v2 の本文
2. [`03-five-decisive-fixes.md`](03-five-decisive-fixes.md) — 6 つの決定的対策 (コア 4 + adapter 2) の実装
3. [`04-convergence-patterns.md`](04-convergence-patterns.md) — 収束判定基準
4. [`05-env-lint-checklist.md`](05-env-lint-checklist.md) — 環境系 lint 14 項目 (事前撲滅)

## 実プロジェクトでの運用と実証

このツールキットは AIFCC (`aifcc.jp`) コミュニティの 4 プロジェクト + Whisper + ffmpeg コードパイプライン (video-subtitler) で運用しています。**運用経験は 5 プロジェクト、公開できる数値実証は 3 ケース** です:

| プロジェクト | 系統 | 運用範囲 | 公開数値 |
|---|---|---|---|
| Workshop (`workshop.aifcc.jp`) | ランブック | プログラミング基礎教材 / Course 1 ランブック | **4 ラウンドで scope cut → v3.4 確定 (数値実証あり)** |
| SIFT (`sift.aifcc.jp`) | ランブック | AI 仕分けプログラム / Phase C ランブック | **13 ラウンドで ALL PASS (数値実証あり)** |
| video-subtitler (`5dmgmt/video-subtitler`) | コードベース | Whisper + ffmpeg 字幕生成パイプライン | **5 周で H/M/L 下降収束 (数値実証あり / 残 M16+L10 は次セッション判断)** |
| RUN (`run.aifcc.jp`) | ランブック | 運用フェーズプログラム / Course 1-5 監査 | 適用中 / 数値未公開 |
| CPN (`cpn.aifcc.jp`) | ランブック | CCA-F 試験対策 / 受講開始前の最終磨き上げ | 適用中 / 数値未公開 |

`examples/` には Workshop 4R / SIFT 13R / video-subtitler 5R の抜粋と比較分析を収録しています (RUN / CPN の抜粋は未収録)。
