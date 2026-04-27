# 03. 5 つの決定的対策

## 位置づけ

[`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) の五月雨防止プロンプトだけでは ALL PASS に到達しないケースがあります。これは Codex 側のプロンプト設計とは別軸の **ランブック / 監査基盤の構造的欠陥** によるものです。

SIFT Phase C ランブックを 13 ラウンド回した経験から、**この 5 つを最初から織り込めば短いラウンドで PASS に到達しやすくなる** という仮説に基づく対策です (具体的なラウンド数は対象により大きく異なる)。

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

> 補足: `scripts/codex-audit-prompt-gen.sh` は `git rev-parse --short HEAD` (短縮 SHA) を使っているが、監査ログとしての堅牢さを優先するなら呼び出し側で full SHA を export してから generator を呼ぶ運用も可能 (生成 prompt 内の `__SHA__` は短縮形のままだが、ランブック側で full SHA を別途記録)。

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

5 つ全部 ✅ なら、五月雨防止プロンプト v2 と組み合わせて短いラウンドで PASS に到達しやすくなります。

### 5 fixes と docs/05 環境系 lint 14 項目の対応関係

5 fixes は **構造系** (commit pin / canonical baseline / fail-fast / shell 互換 / dotenv) で、docs/05 14 項目は **環境系の機械検出可能パターン**。重複と補完関係:

| 5 fixes | docs/05 14 項目との関係 |
|---|---|
| Fix 1 commit pin | 14 項目 #4 (git diff SHA pin) と部分重複 / 14 項目 #12 (codex sandbox) と運用文脈で関連 |
| Fix 2 canonical baseline | 14 項目には対応なし (構造系 / paste 検証固有) |
| Fix 3 独立変数 fail-fast | 14 項目には対応なし (構造系 / shell スニペット品質) |
| Fix 4 BSD sed 互換 | 14 項目 #1 (BSD sed/grep) と #2 (sed -i) を canonical 形に統一 |
| Fix 5 dotenv 全表記 | 14 項目 #8 (dotenv 4 load slot + 6 表記) を実効値優先順位含めて拡張 |

**5 fixes だけでは docs/05 の以下が未確認のまま残ります**: #3 zsh brace、#5 PORT pin、#6 curl status、#7 next-env.d.ts、#9 .env.local commit、#10 secret echo、#11 printf vs echo、#13 heredoc quoted、#14 cwd 絶対パス。これらは docs/05 を別途必須実行してください。

## 関連文書

- [`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) — 五月雨防止プロンプト v2 (Codex 側プロンプト設計)
- [`05-env-lint-checklist.md`](05-env-lint-checklist.md) — Codex に出す前の環境系 lint 14 項目
