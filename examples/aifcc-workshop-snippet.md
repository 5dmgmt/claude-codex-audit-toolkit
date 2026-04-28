# aifcc-workshop — Next.js + Supabase コードベース監査 R1 (dogfooding)

> 本リポ v0.5-nextjs-supabase 特化方針への遷移直後の **dogfooding 監査**。aifcc-workshop (`workshop.aifcc.jp`) を本リポの code-audit-runbook.md ベースで監査した R1 結果。video-subtitler (Whisper+ffmpeg pipeline / Next.js + Supabase 範囲外) に続いて、Next.js + Supabase での Fix 6 横断 6 観点 ULTRATHINK の機能実証ケースとして N=2 に拡張。

## 概要

- **対象**: `5dmgmt/aifcc-workshop` (Next.js 16 + React 19 + TypeScript 5.9 + Supabase Auth + RLS + Vercel)
- **commit**: `d3d5bfb` (R1 投入時の HEAD)
- **monitor / model**: `gpt-5.4 xhigh` + `--skip-git-repo-check`
- **規模**: app/ 約 74,000 行 (中規模)
- **AUDIT_RUNBOOK.md**: aifcc-workshop ルートに新規追加 (Workshop 側 commit `81d1c9e`)

## R1 結果

**[総合判定: Critical×0 + High×3 + Medium×5 + Low×0]**

### High 3 件 (認証・認可)

| # | 場所 | 概要 |
|---|---|---|
| H1 | `proxy.ts:162` | 旧 `aifcc_session` cookie が proxy / server auth から見えず、ログイン直後に未認証へ戻る (`fdc_session` 移行期の漏れ) |
| H2 | `proxy.ts:82` | `copyCookies()` で `HttpOnly` / `Secure` / `SameSite` / `Path` / `Expires` が剥がれる (Supabase refresh / PKCE verifier の保護崩れ / `app/api/auth/login/route.ts:103` も同パターン) |
| H3 | `app/api/workspaces/[workspaceId]/notifications/route.ts:218` | POST で membership 未検証 → 認証済みユーザーが任意 workspace / 別 tenant の通知を偽造可能 |

### Medium 5 件 (race / 非原子性 / 認可不整合 / 入力検証)

| # | 場所 | 概要 |
|---|---|---|
| M1 | `app/api/workshop/progress/route.ts:133` | read-modify-write race で 2 タブ同時更新で取りこぼし |
| M2 | `app/api/workshop/view-time/route.ts:51` | 閲覧時間加算が非原子的 + 戻り値未検査で error が `success: true` に化ける |
| M3 | `app/api/auth/callback/route.ts:513` (+ `:723` legacy) | 二重 callback で重複 workspace 作成 |
| M4 | `app/api/admin/workshop/organizations/[orgId]/workspaces/route.ts:176` | `workspace_members.role` の大小文字が write path (`'owner'`) と認可/RLS (`'OWNER'`) で不一致 |
| M5 | `app/api/session-notes/share/email/route.ts:24` | client 提供 `shareUrl` / `senderName` を信用 → `noreply@aifcc.jp` 名義の phishing 導線 |

## Fix 6 横断 6 観点との対応 (Next.js + Supabase 文脈での機能実証)

| 観点 | 検出件数 | 代表 finding |
|---|---|---|
| セキュリティ | 3 件 | H2 cookie 属性 / H3 membership 未検証 / M5 phishing |
| 並行性 | 3 件 | M1 progress race / M2 view-time race / M3 callback 重複 |
| データフロー整合性 | 2 件 | H1 cookie 名移行期 / M4 role 大小文字 |
| 例外伝播 | 1 件 (部分) | M2 view-time の戻り値未検査 |
| リソース管理 | 0 件 | (R1 では直接該当なし) |
| エッジケース | 0 件 | (R1 では直接該当なし) |

= **Fix 6 6 観点のうち 4 観点で実 finding** = video-subtitler 1 ケースから N=2 に拡張、Next.js + Supabase 文脈でも有効性を支持する観察。

## ランブック監査ケースとの対比

| 軸 | aifcc-workshop コードベース R1 (本ケース) | video-subtitler コードベース 5R | SIFT / Workshop ランブック監査 |
|---|---|---|---|
| 系統 | コードベース | コードベース | ランブック |
| 監査対象規模 | 中 (app/ 74k 行) | 中 (Whisper+ffmpeg pipeline) | 単一 ランブック .md |
| 推奨 model | `gpt-5.4 xhigh` | `gpt-5.4 xhigh` | `gpt-5.5 xhigh` |
| 必須オプション | `--skip-git-repo-check` | `--skip-git-repo-check` | (不要) |
| Fix 6 適用 | R1 から横断 6 観点 ULTRATHINK 投入 | **Fix 6 不在で 5 周** (反省ケース) | 該当観点のみ適用 |
| R1 件数 | C×0 / H×3 / M×5 / L×0 | H×4 / M×4 / L×2 | 多数 (40-60+ 件) |
| 性質 | 本番 SaaS の認証・認可・race | pipeline の時間軸 / 並行 / 原子性 | 文書整合 / 表現決定性 / 再現性 |

aifcc-workshop の R1 で **Critical 0 + 高優先 finding が認証・認可に集中** したのは、本リポの Fix 6 が「セキュリティ / 並行性 / データフロー整合性」を予防的に押さえる 1 周目として機能したためで、video-subtitler のように 1 周目に観点を洗わず 5 周式運用になる失敗を回避できている。

## 教訓 (本ケースから抽出)

### 1. Next.js + Supabase での Fix 6 適用は有効

aifcc-workshop の R1 で出た 8 件はすべて **Fix 6 6 観点** のうち 4 観点 (セキュリティ / 並行性 / データフロー整合性 / 例外伝播) の組み合わせで説明できる。Whisper+ffmpeg pipeline (video-subtitler) と Web アプリ (aifcc-workshop) で **観点は共通だが具体リスクが違う**:

- pipeline → ファイル原子性 / ffmpeg コマンド注入 / 時間軸前後関係
- Web アプリ → Supabase RLS / 認証 cookie 属性 / Server Action race / 移行期 cookie 名

監査軸 (`AUDIT_RUNBOOK.md` の §監査軸) を framework 別に **具体化** することで観点が機能する。抽象 6 観点だけでは Codex が文脈を読みにくい。

### 2. 移行期コードは Fix 6「データフロー整合性」で発見されやすい

H1 (`aifcc_session` vs `fdc_session` vs Supabase Auth) と M4 (`role` の大小文字) は、両方とも **「途中で実装が変わった結果の不整合」**。aifcc-workshop の `CLAUDE.md` には「`fdc_session` は移行期間のフォールバックのみ / 新規実装では使わない」と明記されているにもかかわらず、proxy 層と server auth 層で参照漏れが発生していた。

= ドキュメントの「使わない」明示と実装の「使われ続けている」を **コード grep + Codex 横断観点** で照合するのが効果的。

### 3. AUDIT_RUNBOOK.md は repo 直下が読みやすい

aifcc-workshop に `AUDIT_RUNBOOK.md` を **repo ルートに新規ファイル** として置いたが、これは Codex が `--skip-git-repo-check` で repo 全体を読む際に最も発見しやすい配置。`docs/AUDIT_RUNBOOK.md` でも動くが、ルートの方が「監査専用ファイル」と一目で分かる。

### 4. dogfooding の意義

本リポを v0.5-nextjs-supabase 特化に絞り込んだ直後の dogfooding として:

- 「Next.js + Supabase 共通」と分類した Fix 1/3/4/6 + docs/05 9 項目が実際に機能した
- 「pattern: Next.js + 自前 auth」(`docs/06`) は aifcc-workshop の `proxy.ts` / `getCurrentUser` 等の構造を見るのに転用可能 (Supabase Auth pattern の正本は v1.0 で `docs/06-supabase-auth.md` 整備予定)
- N=2 (video-subtitler / aifcc-workshop) でも framework 中立を主張するには弱い (`CONTRIBUTING.md` の N=1 仮説制約に従う)

## 今後 (R2 以降の方針)

- R1 High 3 件 (proxy 移行期 + cookie 属性 + notifications membership 未検証) を 1 件ずつ atomic 修正 → R2 で再監査
- 各修正は aifcc-workshop の `CLAUDE.md` 必須コマンド (`npm run type-check && npm run lint && npm run build`) を通してから main 直 push
- AUDIT_RUNBOOK.md 末尾の `## 監査履歴` テーブルに R1 反映済を蓄積、五月雨防止プロンプト v2 の precondition として R2 prompt に転記
- Medium 5 件は R2 で fix or 別 PR 化を判断 (race / 非原子性は単独修正でいいが、role 大小文字は migration が要る)

## 関連文書

- [`docs/01-overview.md`](../docs/01-overview.md) — ランブック監査 vs コードベース監査の 2 系統分岐
- [`docs/03-five-decisive-fixes.md`](../docs/03-five-decisive-fixes.md) — Fix 6 横断 6 観点 ULTRATHINK
- [`docs/07-runbook-templates/code-audit-runbook.md`](../docs/07-runbook-templates/code-audit-runbook.md) — コードベース監査用テンプレ
- [`video-subtitler-snippet.md`](video-subtitler-snippet.md) — video-subtitler 5R (Next.js + Supabase 範囲外のコードベース監査応用例)
- [`comparison-4r-vs-13r.md`](comparison-4r-vs-13r.md) — 3 ケース比較 (本ケース未統合 / R2 完了後に統合検討)
