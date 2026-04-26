# 05. 環境系 lint 14 項目チェックリスト

## 位置づけ

Codex に出す前に Claude Code 側で **機械的に撲滅できる defect** を全部潰しておくためのチェックリスト。これらは Codex に出すと必ず指摘されますが、見つかってからラウンドを 1 つ消費するのは時間の無駄です。

SIFT 監査 12 ラウンド事案で抽出した、**環境依存・実行系の 14 項目**:

## チェックリスト

### 1. BSD sed / grep 互換 (`[[:space:]]` 採用)

```bash
# NG (GNU only)
sed 's/\s*$//' file.txt
grep '\d+' file.txt

# OK (POSIX / BSD 両対応)
sed 's/[[:space:]]*$//' file.txt
grep -E '[0-9]+' file.txt
```

### 2. BSD sed `-i` の引数違い

```bash
# GNU
sed -i 's/foo/bar/' file.txt

# BSD (macOS)
sed -i '' 's/foo/bar/' file.txt

# 両対応 (推奨)
sed -i.bak 's/foo/bar/' file.txt && rm -f file.txt.bak
```

### 3. zsh brace 展開の落とし穴

```bash
# bash では動くが、zsh では nomatch エラーになり得る
ls *.{ts,tsx}

# どちらでも動く
ls *.ts *.tsx
```

### 4. git diff SHA 固定

```bash
# NG (HEAD 動く)
git diff main..HEAD

# OK (固定 SHA)
TARGET_SHA=$(git rev-parse --short HEAD)
git diff main..$TARGET_SHA
```

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

### 8. dotenv 全表記対応 (`.env` / `.env.local` / `.env.production` / `.env.development`)

[`03-five-decisive-fixes.md` Fix 5](03-five-decisive-fixes.md#fix-5-dotenv-全表記対応--nextjs-4-ファイル全部) 参照。**4 ファイル全部 + 6 表記全部** をランブックに明記。

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
Terminal A: cd ~/sandbox/aifcc-workshop-clone  # 受講者
Terminal B: cd ~/Plugins/aifcc-workshop        # 教材修正
```

ランブック内のすべての `cd` / `git -C` は **絶対パス** で書く (相対パスは禁止)。

## 自動実行スクリプト

[`scripts/env-lint-check.sh`](../scripts/env-lint-check.sh) で 14 項目を機械的にチェック可能:

```bash
./scripts/env-lint-check.sh path/to/runbook.md
```

主な検出:
- `\s` `\t` `\d` (BSD 非互換)
- `sed -i` 単独 (BSD 非互換)
- `echo "$SECRET_VAR"` パターン (秘密漏洩)
- 相対パス `cd ./` `git -C ./`

## チェックリスト

ランブックを Codex に出す前に確認:

- [ ] BSD sed 互換 (`[[:space:]]`)
- [ ] BSD sed `-i ''` (空文字 backup) 採用
- [ ] zsh brace 展開を避ける
- [ ] git diff は SHA 固定
- [ ] port は明示
- [ ] curl は `%{http_code}` で status 取得
- [ ] `.gitignore` に `next-env.d.ts`
- [ ] dotenv 4 ファイル全部考慮
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
