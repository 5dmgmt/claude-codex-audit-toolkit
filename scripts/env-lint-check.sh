#!/usr/bin/env bash
#
# 環境系 lint 14 項目チェックスクリプト
#
# 使い方:
#   ./scripts/env-lint-check.sh path/to/runbook.md
#
# 終了コード:
#   0: 全項目 PASS
#   1: 1 つ以上の項目で違反検出
#

set -euo pipefail

TARGET="${1:-}"
: "${TARGET:?Usage: $0 <runbook-path>}"
[ -f "$TARGET" ] || { echo "File not found: $TARGET" >&2; exit 1; }

VIOLATIONS=0

check() {
  local name="$1"
  local pattern="$2"
  local message="$3"

  if grep -nE "$pattern" "$TARGET" > /tmp/lint_match.txt 2>/dev/null && [ -s /tmp/lint_match.txt ]; then
    printf '\033[31m[FAIL]\033[0m %s\n' "$name"
    printf '       %s\n' "$message"
    while IFS= read -r line; do
      printf '       %s\n' "$line"
    done < /tmp/lint_match.txt
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    printf '\033[32m[PASS]\033[0m %s\n' "$name"
  fi
}

echo "=== 環境系 lint 14 項目チェック ==="
echo "対象: $TARGET"
echo

# 1. BSD sed 非互換: \s \t \d
check "1. BSD sed 互換 (\\s / \\t / \\d 不使用)" \
  '(sed|grep)[^|]*\\[std]' \
  '\\s \\t \\d は GNU 専用。POSIX [[:space:]] [0-9] を使用してください'

# 2. BSD sed -i (空文字 backup)
check "2. BSD sed -i 互換 (sed -i '' or sed -i.bak)" \
  "sed -i [^'\\.]" \
  "sed -i は BSD で fail。sed -i '' か sed -i.bak を使用してください"

# 3. zsh brace 展開
check "3. zsh brace 展開を避ける" \
  '\*\.\{[a-z,]+\}' \
  '*.{ts,tsx} は zsh で nomatch エラー。*.ts *.tsx と展開してください'

# 4. git diff SHA 固定
check "4. git diff SHA 固定 (HEAD 不使用)" \
  'git diff [a-z]+\.\.HEAD' \
  'HEAD は動く。git rev-parse --short HEAD で固定 SHA を取ってください'

# 5. port pin
check "5. port 明示 (npm run dev に PORT 指定)" \
  '^[[:space:]]*npm run dev[[:space:]]*$' \
  'PORT=XXXX npm run dev で明示してください'

# 6. curl の status 取得
check "6. curl で status code 取得 (-w %{http_code})" \
  'curl [^|]*https?://[^|]*$' \
  'curl の status code を %{http_code} で取得していますか?'

# 10. process.env の値を出力
check "10. process.env の値を echo しない" \
  'echo[[:space:]]+"\$[A-Z_]+"' \
  'echo "$VAR" は秘密漏洩リスク。[ -n "$VAR" ] で有無のみ判定してください'

# 11. printf vs echo (env add 文脈)
check "11. echo ではなく printf '%s' を使用 (env 文脈)" \
  'echo[[:space:]]+"\$[A-Z_]+"[[:space:]]*\|[[:space:]]*(vercel|op)' \
  'echo は末尾改行混入。printf '\''%s'\'' を使用してください'

# 12. read-only モード
check "12. codex exec は -s read-only で投入" \
  'codex (exec|review)[^|]*$' \
  'codex 実行時に -s read-only が指定されていますか?'

# 14. cwd 絶対パス
check "14. cd / git -C は絶対パス (相対パス禁止)" \
  '^[[:space:]]*(cd|git -C)[[:space:]]+\.{1,2}/' \
  '相対パスは禁止。$HOME / $PWD / 絶対パスで書いてください'

echo
if [ "$VIOLATIONS" -eq 0 ]; then
  printf '\033[32m✅ 全項目 PASS — Codex 監査投入 OK\033[0m\n'
  exit 0
else
  printf '\033[31m❌ %d 項目で違反検出 — 修正してください\033[0m\n' "$VIOLATIONS"
  exit 1
fi
