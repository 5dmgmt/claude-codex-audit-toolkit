# 03. 6 つの決定的対策 (フレームワーク中立 4 + adapter 2)

## 位置づけと適用範囲

[`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) の五月雨防止プロンプトだけでは ALL PASS に到達しないケースがあります。これは Codex 側のプロンプト設計とは別軸の **ランブック / 監査基盤の構造的欠陥** によるものです。

本ドキュメントの Fix は **フレームワーク中立** と **adapter (環境固有)** の 2 階層に整理されています:

| Fix | 階層 | 適用範囲 | 出典実証 |
|---|---|---|---|
| Fix 1: commit pin + dirty check + snapshot 確認 | **コア (中立)** | 全プロジェクト | SIFT 13R / Workshop 4R / video-subtitler 5R 全部 |
| Fix 2: canonical baseline (DOM API 選定) | **adapter (Web UI / DOM 検証)** | Web UI / DOM 検証を含むプロジェクトのみ (CLI ツール / 動画 pipeline では非該当) | SIFT 13R (paste 動線検証) |
| Fix 3: 独立ブロック変数 fail-fast | **コア (中立)** | 全プロジェクト (shell スニペット品質) | SIFT 13R / Workshop 4R 共通 |
| Fix 4: BSD sed / grep 互換 | **コア (中立)** | macOS + Linux 両対応の shell スニペットを書く全プロジェクト | SIFT 13R で確立 |
| Fix 5: dotenv 全表記対応 + load slot | **adapter (Next.js 固有)** | Next.js プロジェクト | SIFT / Workshop は Next.js 16 |
| Fix 6: 横断 6 観点 ULTRATHINK | **コア (中立)** — コードベース監査で必須 / ランブック監査でも該当観点を適用 | コードベース監査全般 + ランブック監査の一部観点 | video-subtitler 5R (Fix 6 不在で五月雨式運用になった反省) |

> **N=1 の注意**: Fix 5 (Next.js dotenv) は SIFT/Workshop の 2 ケース、Fix 6 (横断 6 観点) は video-subtitler の 1 ケースから抽出した仮説です。他の framework / 他のコードベースでの汎化は要検証。Rails / Django / Go 等の adapter を別途定義する余地があります ([CONTRIBUTING.md](../CONTRIBUTING.md) 参照)。

## Fix 1. commit pin + dirty check + snapshot 確認

### 問題

監査開始後にランブックを修正すると、Codex が見ているスナップショットと現状が乖離し、「もう直したのにまた指摘してくる」「見ている SHA が違うから検証できない」が起きます。

### 対策

監査前に **(a) 変更を commit / (b) full SHA 取得 / (c) dirty tree fail-fast / (d) snapshot 内ファイル存在確認** を全部やり、その上で `scripts/codex-audit-prompt-gen.sh` を使う:

```bash
# (a) 変更を commit (未コミット修正があると次の SHA は古いまま)
git add -A && git commit -m "..."

# (b) full SHA 取得 (--short は監査証跡として弱い)
TARGET_SHA=$(git rev-parse HEAD)

# (c) dirty tree fail-fast
STATUS_OUT=$(git status --porcelain=v1 --untracked-files=all 2>&1)
[ -z "$STATUS_OUT" ] || { echo "FAIL: dirty tree"; echo "$STATUS_OUT"; exit 1; }

# (d) snapshot 内に対象ファイルが存在することを確認
git cat-file -e "$TARGET_SHA:docs/foo.md" \
  || { echo "FAIL: docs/foo.md not in $TARGET_SHA"; exit 1; }

# generator (内部で sed '/^##/d' + 4 placeholder 置換)
./scripts/codex-audit-prompt-gen.sh \
  --runbook docs/foo.md \
  --runbook-name "Foo ランブック" \
  --prev-findings "初回" > /tmp/prompt.txt

codex exec -s read-only -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  --output-last-message /tmp/codex-result.md \
  "$(cat /tmp/prompt.txt)" < /dev/null
```

ランブックには監査対象として:

```markdown
## 検査対象
- commit: `__SHA__` (full SHA / 固定)
- branch: main
- 監査対象: `git show __SHA__:__RUNBOOK_PATH__` のスナップショット (作業ツリーではなく commit 内容)
- 前提: dirty tree fail-fast 済 + snapshot に対象ファイル存在確認済
```

ラウンド間でランブック修正が入ったら、必ず新しい SHA で `__SHA__` 置換してから出す。**Codex が見るのは固定 commit のスナップショットのみ**。

> 注: `scripts/codex-audit-prompt-gen.sh` は `git rev-parse HEAD` (full SHA) を内部で使うように 12e7e95 で修正済。生成 prompt 内の `__SHA__` も full SHA に置換される。

## Fix 2. canonical baseline (DOM API の選定統一)

### 問題

ランブックに「テキストを取得して比較」と書くと、Codex のラウンドごとに `textContent` / `innerText` / `innerHTML` の選び方が揺れて、ラウンドごとに違う指摘が出ます。

### 対策

**1 つの canonical baseline** を選定して全ランブックで統一:

| API | canonical 採用 | 理由 |
|---|---|---|
| `element.textContent` | ❌ 不採用 | hidden / `display:none` も拾う / 改行区切りなし |
| `element.innerText` | ✅ **canonical** | レンダリング後のユーザー可視テキスト / 改行区切り適切 |
| `element.innerHTML` | ❌ 不採用 | HTML タグ含む / 比較ノイズが大きい |

ランブックの検査基準には:

```markdown
- 検査基準: `element.innerText` (canonical baseline、`textContent` / `innerHTML` は使用禁止)
- 取得コンテキスト: Playwright Chromium で page load 後 (DOMContentLoaded + 1 描画フレーム待機) に取得
- 正規化: 改行コード `\n` 統一 / 前後空白 trim / NBSP / zero-width space は事前 strip
```

を必ず明記。Codex が prompt を再読しても揺れません (CLI/Node/jsdom 文脈では innerText 仕様が異なるので、Playwright 等のブラウザ実行環境で baseline を取る)。

## Fix 3. 独立ブロック変数 fail-fast (env / config の verify)

### 問題

ランブックに「`.env.local` を確認」と書くだけだと、変数が unset でも空文字でも fall-through して、後段で謎のエラーが出ます。

### 対策

ランブック冒頭に **独立ブロックで env / config 変数を verify** し、未設定なら即 fail (最小例。実運用では `scripts/codex-audit-prompt-gen.sh` の必須変数に従う):

```bash
: "${TARGET_SHA:?TARGET_SHA is required}"
: "${RUNBOOK_PATH:?RUNBOOK_PATH is required}"
: "${RUNBOOK_NAME:?RUNBOOK_NAME is required}"
: "${TEMPLATE_PATH:?TEMPLATE_PATH is required}"
[ -f "$RUNBOOK_PATH" ] || { echo "Runbook not found: $RUNBOOK_PATH"; exit 1; }
[ -f "$TEMPLATE_PATH" ] || { echo "Template not found: $TEMPLATE_PATH"; exit 1; }
```

POSIX `${VAR:?msg}` は **unset / 空文字どちらでも fail** する確実な書き方。
Codex に出すランブックには「変数 verify ブロックは独立 (検査ロジックと混ぜない / 失敗時は即 exit)」を明記する。

## Fix 4. BSD sed / grep 互換 (`[[:space:]]` + `sed -i.bak` 採用)

### 問題

GNU sed は `\s` `\t` を解釈しますが、**macOS の BSD sed は解釈しません**。GNU 前提でランブックを書くと、Codex のレビュー環境 (Linux) では PASS でも、ユーザーの mac で再現できないケースが起きます。

### 対策

POSIX 準拠の **`[[:space:]]` クラス** + 両対応 canonical の **`sed -i.bak`** を全面採用 (docs/05 と同じ baseline):

| 用途 | NG (環境依存) | OK (両対応 canonical) |
|---|---|---|
| 空白 | `\s` `\t` | `[[:space:]]` |
| 数字 | `\d` (PCRE 依存) | `[0-9]` `[[:digit:]]` |
| 行末空白除去 | `sed 's/\s*$//'` | `sed 's/[[:space:]]*$//'` |
| in-place | `sed -i` (GNU) / `sed -i ''` (BSD) | `sed -i.bak 's/foo/bar/' file && rm -f file.bak` |

ランブックの shell スニペットは **両対応形で書いて、macOS と Linux の両方で動作確認** する。`grep -E` (extended) も POSIX 準拠で書く (`grep -P` は PCRE 依存なので避ける)。

## Fix 5. dotenv 全表記対応 + Next.js の load slot

### 問題

`.env` だけ確認するランブックを書くと、本番では `.env.production`、開発では `.env.local` を読んでいて齟齬が出ます。Next.js は 4 種類の dotenv ファイルがあり、優先順位も決まっています。

### 対策

ランブックに **実効値の優先順位 (process.env 含む)** + 4 load slot + 6 表記を明記:

```markdown
### Next.js の実効値優先順位 (5 段)

1. `process.env` (実環境変数) — 最優先 (.env ファイルで上書きされない)
2. `.env.$NODE_ENV.local` — 環境別 local override (gitignore)
3. `.env.local` — 全環境 local override (gitignore、test 環境では無視)
4. `.env.$NODE_ENV` — 環境別 load
5. `.env` — 全環境 default

`$NODE_ENV` は実行時に `development` / `production` / `test` のいずれかが選ばれ、
2-5 が **「現在の NODE_ENV に対する 4 load slot」** を構成する。
具体的なファイル列挙ではなく **load pattern** として理解する。

検査時は **process.env を最優先で確認 + 4 load slot 全部確認 + 優先順位の重複排除を追跡**。
ファイルだけを追跡すると、実環境変数で上書き済みの値を誤判定する。

参照: https://nextjs.org/docs/pages/guides/environment-variables
```

dotenv 表記の揺れも同時に対応:

| 表記 | 解釈 |
|---|---|
| `KEY=value` | 標準 |
| `KEY="value"` | quote 付き (空白含む値) |
| `KEY='value'` | 単一 quote (展開しない) |
| `KEY=` | 空文字 (unset と区別) |
| `# KEY=value` | コメント (無視) |
| `export KEY=value` | shell 互換 (Next.js は export を strip) |

Codex に出すプロンプトには「dotenv 検査は **process.env 優先順位 + 4 load slot + 上記 6 表記全部**」を明記。

## Fix 6. 反復監査の 1 周目で横断 6 観点 ULTRATHINK を全部洗う

### 問題

外部監査 (Codex) を反復で回す際、Codex の指摘を待ってから 1 件ずつ反応するパターンに陥ると、**周回ごとに新規の構造的バグが発見されて五月雨式運用** になる。`5dmgmt/video-subtitler` のコードベース監査で 5 周回した実例では、周 2-4 で「時間軸不整合 / 並行実行衝突 / 原子性欠如 / パストラバーサル」が逐次発見され、これらは観点を最初に列挙していれば 1 周目で気づけたものだった ([詳細](../examples/video-subtitler-snippet.md))。

### 対策

**反復監査の 1 周目に、自己 ULTRATHINK で横断 6 観点を全部洗う**:

1. **セキュリティ** — 注入 (SQL / コマンド / template) / パストラバーサル / 権限昇格 / RBAC 漏洩 / secret 露出
2. **並行性** — race condition / lock / atomicity / last-writer-wins / 並列実行時の output 衝突
3. **データフロー整合性** — 時間軸の前後関係 / スキーマ整合 / 依存関係順序 / 一貫性ガード
4. **例外伝播** — 外部ライブラリ例外 / OS エラー (ENOENT / EACCES) / ユーザー入力の空 / 不正値の扱い
5. **リソース管理** — 一時ファイル cleanup / メモリリーク / ハンドル close / 並行実行時の連鎖枯渇
6. **エッジケース** — 空入力 / 境界値 (0 / 1 / max) / nan / inf / 超巨大入力 / 文字エンコーディング

これを 1 周目に **予防的に押さえる**。Codex 監査は「答え合わせ / 最終チェック」に格下げする。

### コード監査向けテンプレ

`docs/07-runbook-templates/code-audit-runbook.md` の冒頭にこの 6 観点を列挙して、各観点で本リポにどんな具体リスクがあるかを 3-5 件ずつ書き出してから実装に着手する。書き出した観点が監査軸そのものになる。

### ランブック監査では?

ランブック監査でも適用可能だが、**焦点は変わる**:

| 観点 | ランブック監査での解釈 |
|---|---|
| セキュリティ | 秘密漏洩例 / 認証バイパス例の混入 |
| 並行性 | (該当少ない) cwd 並列作業の混乱 / 排他確認手順 |
| データフロー整合性 | セクション間の整合 / 数値・命名・前提の一貫性 |
| 例外伝播 | 失敗時の判定基準 / 検証コマンドの exit code 区別 |
| リソース管理 | 一時ファイル / port pin / dev server cleanup |
| エッジケース | 空 input / 末尾空白 / NBSP / 改行コード |

### 効果

video-subtitler では Fix 6 (= ULTRATHINK 6 観点) を **適用しなかった結果として 5 周回す羽目になった**。今後の反復監査では Fix 6 を適用することで 2-3 周で収束する仮説 (要検証)。

## 効果実証

### 時系列で見た効果 (SIFT Phase C / Workshop Course 1 の 2 ケース観察)

| 期間 | 状態 | 指摘の傾向 |
|---|---|---|
| SIFT R1-R3 | v2 / 5 fixes 未適用 | 「同じ env 関連の指摘が繰り返し出る」「BSD sed で動かないスニペットが指摘される」「commit が動いて検証不能」 |
| SIFT R4 | v2 (4 行ブロック + 蓄積リスト) 導入 | R3=18 → R4=6 に大幅減 (主因は v2 の cascade 防止仕掛け) |
| SIFT R5-R12 | v2 + 5 fixes 適用後の低位推移 | 環境系・再現性系の defect が落ち着き、構造的議論や dev bypass 系の論点に集中 |
| SIFT R13 | bypass 4 原則を含めて反映完了 | ALL PASS |
| Workshop R1 | v2 / 5 fixes 未適用 | 40 件のうち多くが fix 1-5 で防げる種類の defect |
| Workshop R2 | v2 部分適用 | R1=40 → R2=13 (主因は v2、5 fixes は次ラウンドへ) |
| Workshop R3 | v2 + 5 fixes 完全適用 | R2=13 → R3=6 で再現性系・環境系 defect が消えやすくなった |

### 観察された効果

- 環境系・再現性系の defect が R1 で出やすくなる → R2 以降の論点を絞りやすい
- 「commit が動いて検証不能」が解消されやすい
- BSD/GNU 互換性の指摘が減りやすい (アプリ固有の defect は別途対処)

## チェックリスト

ランブックを Codex に出す前に確認:

- [ ] commit SHA が `__SHA__` placeholder で固定 + `git show __SHA__:__RUNBOOK_PATH__` で監査対象スナップショットを明記
- [ ] DOM API は `element.innerText` を canonical baseline として明記 + 取得コンテキストを Fix 2 と同粒度で記載 (Playwright Chromium / DOMContentLoaded + 1 描画フレーム待機 / 改行・前後空白・NBSP・zero-width space 正規化)
- [ ] env / config 変数は独立ブロックで verify、未設定なら即 fail (運用では generator の必須変数に従う)
- [ ] sed / grep は `[[:space:]]` 採用 + `sed -i.bak` 両対応形 (canonical baseline は docs/05 と統一)
- [ ] dotenv は実効値優先順位 (process.env 最優先) + 4 load slot + 6 表記すべて検査対象に明記
- [ ] **横断 6 観点 ULTRATHINK** をプロンプト投入前に実施 (セキュリティ / 並行性 / データフロー整合性 / 例外伝播 / リソース管理 / エッジケース)。コード監査では必須、ランブック監査では該当観点を適用

6 つ全部 ✅ なら、五月雨防止プロンプト v2 と組み合わせて短いラウンドで PASS に到達しやすくなります。

### 6 fixes と docs/05 環境系 lint 14 項目の対応関係

Fix 1-5 は **構造系**、docs/05 14 項目は **環境系の機械検出可能パターン**、Fix 6 は **横断観点 ULTRATHINK** (予防的設計レビュー)。docs/05 §適用範囲表の階層分類と一致させた対応:

| Fix | 階層 | docs/05 14 項目との関係 |
|---|---|---|
| Fix 1 commit pin | コア中立 | #4 (git diff SHA pin) と部分重複 / #12 (codex sandbox) と運用文脈で関連 |
| Fix 2 canonical baseline | コア (Web UI 検証あれば) | 14 項目には対応なし (構造系 / paste 検証固有) |
| Fix 3 独立変数 fail-fast | コア中立 | 14 項目には対応なし (構造系 / shell スニペット品質) |
| Fix 4 BSD sed 互換 | コア中立 | #1 (BSD sed/grep) と #2 (sed -i.bak canonical) と直接対応 |
| Fix 5 dotenv 全表記 | **Next.js adapter** | #8 (Next.js adapter / dotenv 4 load slot + 6 表記) を実効値優先順位含めて拡張 |
| Fix 6 横断 6 観点 ULTRATHINK | コア中立 | 14 項目とは別軸 (機械検出ではなく予防的設計レビュー) |

**Fix 1-5 + 14 項目だけでは Fix 6 の予防的観点が抜けます**。コード監査では Fix 6 が必須、ランブック監査でも該当する観点 (主にデータフロー整合性 / 例外伝播 / エッジケース) は適用すべきです。

## 関連文書

- [`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) — 五月雨防止プロンプト v2 (Codex 側プロンプト設計)
- [`05-env-lint-checklist.md`](05-env-lint-checklist.md) — Codex に出す前の環境系 lint 14 項目
