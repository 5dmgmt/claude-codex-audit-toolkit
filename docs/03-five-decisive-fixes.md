# 03. 5 つの決定的対策

## 位置づけ

[`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) の五月雨防止プロンプトだけでは ALL PASS に到達しないケースがあります。これは Codex 側のプロンプト設計とは別軸の **ランブック / 監査基盤の構造的欠陥** によるものです。

SIFT Phase C ランブックを 13 ラウンド回した経験から、**この 5 つを最初から織り込めば 1-3 ラウンドで PASS** に到達する確率が大幅に上がります。

## Fix 1. commit pin + `__SHA__` placeholder で再現性担保

### 問題

監査開始後にランブックを修正すると、Codex が見ているスナップショットと現状が乖離し、「もう直したのにまた指摘してくる」「見ている SHA が違うから検証できない」が起きます。

### 対策

ランブック冒頭に **検査対象 commit SHA** を必ず固定。プロンプトには `__SHA__` placeholder を使い、shell で展開:

```bash
TARGET_SHA=$(git rev-parse --short HEAD)
PROMPT=$(cat docs/07-runbook-templates/codex-audit-prompt.txt)
PROMPT="${PROMPT//__SHA__/$TARGET_SHA}"

codex exec -s read-only -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  "$PROMPT" < /dev/null
```

ランブックには:

```markdown
## 検査対象
- commit: `__SHA__` (固定)
- branch: main
- 確認方法: `git show __SHA__ --stat`
```

ラウンド間でランブック修正が入ったら、必ず新しい SHA で `__SHA__` 置換してから出す。**Codex が見るのは固定 commit のスナップショットのみ**。

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
```

を必ず明記。Codex が prompt を再読しても揺れません。

## Fix 3. 独立ブロック変数 fail-fast (env / config の verify)

### 問題

ランブックに「`.env.local` を確認」と書くだけだと、変数が unset でも空文字でも fall-through して、後段で謎のエラーが出ます。

### 対策

ランブック冒頭に **独立ブロックで env / config 変数を verify** し、未設定なら即 fail:

```bash
: "${TARGET_SHA:?TARGET_SHA is required}"
: "${RUNBOOK_PATH:?RUNBOOK_PATH is required}"
[ -f "$RUNBOOK_PATH" ] || { echo "Runbook not found: $RUNBOOK_PATH"; exit 1; }
```

POSIX `${VAR:?msg}` は **unset / 空文字どちらでも fail** する確実な書き方。
Codex に出すランブックには「変数 verify ブロックは独立 (検査ロジックと混ぜない / 失敗時は即 exit)」を明記する。

## Fix 4. BSD sed / grep 互換 (`[[:space:]]` 採用)

### 問題

GNU sed は `\s` `\t` を解釈しますが、**macOS の BSD sed は解釈しません**。GNU 前提でランブックを書くと、Codex のレビュー環境 (Linux) では PASS でも、ユーザーの mac で再現できないケースが起きます。

### 対策

POSIX 準拠の **`[[:space:]]` クラス** を全面採用:

| 用途 | NG (GNU 専用) | OK (POSIX / BSD 両対応) |
|---|---|---|
| 空白 | `\s` `\t` | `[[:space:]]` |
| 数字 | `\d` | `[0-9]` `[[:digit:]]` |
| 行末改行除去 | `sed 's/\s*$//'` | `sed 's/[[:space:]]*$//'` |
| in-place | `sed -i` | `sed -i ''` (BSD) / `sed -i` (GNU) |

ランブックの shell スニペットは **必ず BSD sed で動くか先に検証** する。`grep -E` (extended) も POSIX 準拠で書く。

## Fix 5. dotenv 全表記対応 + Next.js 4 ファイル全部

### 問題

`.env` だけ確認するランブックを書くと、本番では `.env.production`、開発では `.env.local` を読んでいて齟齬が出ます。Next.js は 4 種類の dotenv ファイルがあり、優先順位も決まっています。

### 対策

ランブックに **全 4 ファイル + 優先順位** を明記:

```markdown
### dotenv ファイル優先順位 (Next.js)

1. `.env.{environment}.local` — 環境別 local override (gitignore)
2. `.env.local` — 全環境 local override (gitignore、test 環境では無視)
3. `.env.{environment}` — 環境別 (`.env.development` / `.env.production` / `.env.test`)
4. `.env` — 全環境 default

検査時は **4 ファイル全て確認 + 優先順位の重複排除を追跡**。
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

Codex に出すプロンプトには「dotenv 検査は 4 ファイル全部 + 上記 6 表記全部」を明記。

## 効果実証

### Before (5 fixes 未適用)

- SIFT Phase C: R1-R12 で「同じ env 関連の指摘が繰り返し出る」「BSD sed で動かないスニペットが指摘される」「commit が動いて検証不能」
- Workshop Course 1: R1 で 40 件、ほぼ全部 fix 1-5 で防げる種類の defect

### After (5 fixes 全適用)

- 環境系・再現性系の defect が **R1 で全部出る** → R2 以降は構造的議論に集中できる
- 「commit が動いて検証不能」が消える
- BSD/GNU 互換性の指摘がゼロ化

## チェックリスト

ランブックを Codex に出す前に確認:

- [ ] commit SHA が `__SHA__` placeholder で固定されている
- [ ] DOM API は `element.innerText` を canonical baseline として明記
- [ ] env / config 変数は独立ブロックで verify、未設定なら即 fail
- [ ] sed / grep は `[[:space:]]` 採用、BSD sed で動作確認済
- [ ] dotenv は 4 ファイル + 6 表記すべて検査対象に明記

5 つ全部 ✅ なら、五月雨防止プロンプト v2 と組み合わせて 1-3 ラウンド PASS の確率が大幅に上がります。

## 関連文書

- [`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) — 五月雨防止プロンプト v2 (Codex 側プロンプト設計)
- [`05-env-lint-checklist.md`](05-env-lint-checklist.md) — Codex に出す前の環境系 lint 14 項目
