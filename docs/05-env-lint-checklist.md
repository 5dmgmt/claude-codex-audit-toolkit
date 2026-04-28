# 05. 環境系 lint 14 項目チェックリスト

## 位置づけ

Codex に出す前に Claude Code 側で **機械的に撲滅できる defect** を全部潰しておくためのチェックリスト。これらは Codex に出すと必ず指摘されますが、見つかってからラウンドを 1 つ消費するのは時間の無駄です。

SIFT Phase C 13 ラウンド事案で抽出した、**環境依存・実行系の 14 項目**:

### 適用範囲

| 項目 | 階層 | 範囲 |
|---|---|---|
| #1 BSD sed/grep / #2 sed -i.bak / #3 zsh brace / #4 git diff SHA pin / #14 cwd 絶対パス | **コア (中立)** | macOS + Linux 両対応の shell スニペットを書く全プロジェクト |
| #10 secret echo / #11 printf vs echo | **コア (中立)** | 全プロジェクト (秘密値の扱い) |
| #13 heredoc quoted | **コア (中立)** | shell スニペット品質 |
| #5 PORT pin (npm run dev) | **adapter (Node.js 系)** | Node.js / npm 系プロジェクト |
| #6 curl status code | **コア (中立)** | curl を使う全プロジェクト |
| #12 codex `-s read-only` | **コア (Codex CLI 固有)** | 本ツールキット利用者全員 |
| #7 next-env.d.ts gitignore / #8 dotenv 4 load slot + 6 表記 / #9 .env.local commit 禁止 | **adapter (Next.js 固有)** | Next.js プロジェクト |

Rails / Django / Go 等の adapter を別途定義する余地があります ([CONTRIBUTING.md](../CONTRIBUTING.md) 参照)。

## 14 項目

### 1. BSD sed / grep 互換 (`[[:space:]]` 採用)

```bash
# NG (非 POSIX / PCRE 依存表記)
sed 's/\s*$//' file.txt
grep '\d+' file.txt
grep -P '\d+' file.txt

# OK (POSIX / BSD 両対応)
sed 's/[[:space:]]*$//' file.txt
grep -E '[0-9]+' file.txt
```

### 2. BSD sed `-i` の引数違い (推奨は `-i.bak`)

GNU/BSD 両対応の canonical baseline は `sed -i.bak ... && rm -f file.bak`。`sed -i ''` は macOS BSD 専用なので、Linux サーバや CI では fail する:

```bash
# 推奨 (GNU / BSD 両対応)
sed -i.bak 's/foo/bar/' file.txt && rm -f file.txt.bak

# macOS 専用 (Linux で fail)
sed -i '' 's/foo/bar/' file.txt

# GNU 専用 (BSD で fail)
sed -i 's/foo/bar/' file.txt
```

### 3. zsh brace 展開の落とし穴

```bash
# bash では動くが、zsh では nomatch エラーになり得る
ls *.{ts,tsx}

# NG (片方の glob に一致がない場合 zsh で失敗)
ls *.ts *.tsx

# OK (find / ripgrep で確実に解決)
find . -maxdepth 1 \( -name '*.ts' -o -name '*.tsx' \)
rg --files -g '*.ts' -g '*.tsx'
```

### 4. git diff の base / target を両方 SHA 固定

```bash
# NG (両方とも動く ref / 後日同じ手順で diff が変わる)
git diff main..HEAD
git diff origin/main..HEAD

# OK (base / target を full SHA で固定)
BASE_SHA=$(git rev-parse main)
TARGET_SHA=$(git rev-parse HEAD)
git diff "$BASE_SHA..$TARGET_SHA"
```

`--short` は監査証跡として弱いので full SHA で固定する。

### 5. port pin (フリーポート期待しない)

```bash
# NG (ポート競合で fail)
npm run dev  # 3000 期待

# OK (明示)
PORT=3001 npm run dev
```

### 6. curl の HTTP status 取得

```bash
# NG (body だけ、status 不明)
curl https://example.com/api

# OK (status code 抽出)
HTTP_CODE=$(curl -s -o /tmp/body.txt -w '%{http_code}' https://example.com/api)
[ "$HTTP_CODE" = "200" ] || { cat /tmp/body.txt; exit 1; }
```

### 7. next-env.d.ts 自動書換対策

Next.js は `npm run dev` 起動時に `next-env.d.ts` を自動生成・書換します。`.gitignore` 漏れがあると差分汚染:

```gitignore
# .gitignore
next-env.d.ts
```

ランブックには「`next-env.d.ts` の差分は無視 (Next.js 自動生成)」と明記。

### 8. dotenv 全表記対応 (実効値優先順位 + 4 load slot + 6 表記)

実効値の優先順位 (Next.js):

1. `process.env` (実環境変数) — 最優先 (.env ファイルで上書きされない)
2. `.env.$NODE_ENV.local` — 環境別 local override (gitignore)
3. `.env.local` — 全環境 local override (gitignore、test 環境では無視)
4. `.env.$NODE_ENV` — 環境別
5. `.env` — 全環境 default

`$NODE_ENV` には `development` / `production` / `test` を入れて 4 load slot に展開する (例: `.env.development.local` / `.env.production` 等)。検査時は `process.env` を最優先で確認 + 4 load slot 全て確認。

dotenv 行表記の 6 パターン (検査対象):

| 表記 | 解釈 |
|---|---|
| `KEY=value` | 標準 |
| `KEY="value"` | quote 付き (空白含む値) |
| `KEY='value'` | 単一 quote (展開しない) |
| `KEY=` | 空文字 (unset と区別) |
| `# KEY=value` | コメント (無視) |
| `export KEY=value` | shell 互換 (Next.js は `export` を strip) |

詳細は [`03-five-decisive-fixes.md` Fix 5](03-five-decisive-fixes.md#fix-5-dotenv-全表記対応--nextjs-全-env-4-ファイル) 参照。

### 9. .env.local のコミット禁止

```bash
# .gitignore
.env*
!.env.tpl
```

`.env.tpl` だけコミット可、その他は除外。1Password CLI の `op inject` でローカル生成。

### 10. process.env の値を出力しない

```bash
# NG (秘密漏洩)
echo "DB_URL=$DB_URL"
cat .env.local

# OK (有無のみ判定)
[ -n "$DB_URL" ] || { echo "DB_URL is unset"; exit 1; }
```

### 11. printf vs echo (改行混入)

```bash
# NG (末尾 \n でキー破損)
echo "$API_KEY" | vercel env add KEY production

# OK
printf '%s' "$API_KEY" | vercel env add KEY production --sensitive
```

### 12. read-only モードで監査投入

Codex 監査は **必ず read-only モード** で投入 (`-s read-only`)。書き込み許可で出すと Codex が勝手に修正を試みて差分汚染:

```bash
codex exec -s read-only -m gpt-5.5 -c model_reasoning_effort="xhigh" "$PROMPT"
```

### 13. heredoc の quote / interpolation 制御

```bash
# 変数展開する heredoc
cat <<EOF
Hello $USER
EOF

# 変数展開しない heredoc (推奨: prompt 等)
cat <<'EOF'
Hello $USER  # ← そのまま $USER と出力
EOF
```

ランブック内のプロンプトテンプレは **必ず `'EOF'` (quoted) を使う**。展開されると秘密漏洩や意図と違う prompt になる。

### 14. cwd 分離 (作業ディレクトリ混乱の防止)

複数リポを並行作業する場合、ターミナル A (受講者シミュレーション) とターミナル B (教材修正) を **物理的に分ける**:

```
Terminal A: cd "$HOME/sandbox/aifcc-workshop-clone"  # 受講者
Terminal B: cd "$HOME/Plugins/aifcc-workshop"        # 教材修正
```

ランブック内のすべての `cd` / `git -C` は **絶対パス または `$HOME` / `$PWD` 展開** で書く (`~` は quoted context で展開されないので避ける、相対パスは禁止)。

## 自動実行スクリプト

[`scripts/env-lint-check.sh`](../scripts/env-lint-check.sh) は 14 項目のうち機械検出しやすい 10 系統を grep ベースでチェックします。**FAIL 検出 / 未実装 (目視) の 2 種類を項目ごとに区別** (現実装には WARN 抽出はありません):

> **限界事項**: grep ベースのため、shell 文脈の完全解析はできません。具体的には: (a) `git diff` の base/target が動く ref かは未 quoted の代表パターンのみ検出、(b) cwd 検出は `cd "./repo"` 等 quoted 相対パスや `git -C "$ANY_VAR"` 等の任意変数を漏らす、(c) #5/#6/#12 の検出は行頭実行コマンド限定 (`NODE_ENV=foo npm run dev` や `HTTP_CODE=$(curl ...)` のような env assignment + command substitution は対応)、(d) #11 の OK 例 `printf '%s' "$VAR" | vercel` は #10 から明示的に除外。完全網羅は目視確認との併用が前提。

| 項目 | scripts/env-lint-check.sh の扱い | 検出ロジック |
|---|---|---|
| #1. BSD sed/grep `\s\t\d` | **FAIL 検出** | sed/grep 行に `\s` `\t` `\d` を含む |
| #2. BSD sed `-i` | **FAIL 検出** | `sed -i` 直後に backup 拡張子 (`.bak` 等) なし |
| #3. zsh brace `*.{ts,tsx}` | **FAIL 検出** | `*.{a,b}` パターン |
| #4. git diff SHA pin | **FAIL 検出** | 動く ref (`main..HEAD` / `HEAD~1..HEAD` 等) を含む |
| #5. PORT pin | **FAIL 検出** | `npm run dev` の同一行に `PORT=` も `--port` もなし |
| #6. curl status code | **FAIL 検出** | `curl` 行に `-w` と `%{http_code}` の両方がない |
| #7. next-env.d.ts gitignore | **未実装 (目視)** | リポルートで `git check-ignore -v next-env.d.ts` |
| #8. dotenv 4 ファイル + 6 表記 | **未実装 (目視)** | docs/05 の 6 表記表で確認 |
| #9. .env.local tracked 禁止 | **未実装 (目視)** | `git ls-files -- '.env*' \| grep -v '\.env\.tpl$'` が空 |
| #10. process.env 値の echo | **FAIL 検出** | 行頭コマンドとして `echo "$VAR"` / `echo "KEY=$VAR"` / `cat .env*` / `printenv` / `env` (引数なし)。`printf '%s' "$VAR" \| (vercel\|op\|aws\|gcloud)` (#11 OK 例) は除外 |
| #11. printf vs echo (env 投入) | **FAIL 検出** | 行頭コマンドとして `echo "$VAR" \| (vercel\|op\|aws\|gcloud)`。`printf '%s'` 形式は OK |
| #12. codex `-s read-only` | **FAIL 検出** | `codex (exec\|review)` 行に `-s read-only` も `--sandbox read-only` もなし |
| #13. heredoc quoted | **未実装 (目視)** | `<<EOF` (unquoted) を grep して文脈確認 |
| #14. cwd 絶対パス | **FAIL 検出** | `cd` / `git -C` 引数が `/` `$HOME` `${HOME}` `$PWD` `${PWD}` 以外 |

```bash
./scripts/env-lint-check.sh path/to/runbook.md
# 終了コード: 0 = 全自動項目 PASS / 1 = 違反検出 / 2 = lint 自体の失敗
```

未実装 4 項目は実行後に PASS メッセージ内で目視必要として明示されます。

## 投入前チェック

ランブックを Codex に出す前に確認:

- [ ] BSD sed 互換 (`[[:space:]]`)
- [ ] sed `-i.bak` 推奨 (両対応) / `sed -i ''` は macOS 専用
- [ ] zsh brace 展開を避ける
- [ ] git diff は SHA 固定
- [ ] port は明示
- [ ] curl は `%{http_code}` で status 取得
- [ ] `.gitignore` に `next-env.d.ts`
- [ ] dotenv: process.env 優先順位 + 4 load slot + 6 表記すべて確認
- [ ] `.env.local` は gitignore (`.env.tpl` のみ commit)
- [ ] `process.env` の値を echo しない
- [ ] `echo` ではなく `printf '%s'` 使用
- [ ] Codex は `-s read-only` で投入
- [ ] heredoc は `'EOF'` (quoted)
- [ ] cwd は絶対パス

14 項目全部 ✅ で Codex に出す。

## 関連文書

- [`03-five-decisive-fixes.md`](03-five-decisive-fixes.md) — 5 つの決定的対策 (構造系)
- [`scripts/env-lint-check.sh`](../scripts/env-lint-check.sh) — 自動チェックスクリプト
