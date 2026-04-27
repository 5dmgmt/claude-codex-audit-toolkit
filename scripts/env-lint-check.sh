#!/usr/bin/env bash
#
# 環境系 lint 自動チェックスクリプト
#
# docs/05-env-lint-checklist.md の 14 項目のうち、機械検出に向く 10 系統を
# grep ベースで自動チェックする。残り 4 項目 (#7 next-env.d.ts gitignore /
# #8 dotenv 4 ファイル / #9 .env.local commit 禁止 / #13 heredoc quoted) は
# 目視確認が必要。詳細は docs/05 を参照。
#
# 使い方:
#   ./scripts/env-lint-check.sh path/to/runbook.md
#
# 終了コード:
#   0: 全自動項目 PASS
#   1: 1 つ以上の項目で違反検出
#   2: lint 自体の失敗 (file not readable / regex error 等)
#

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <runbook-path>" >&2
  exit 2
fi

TARGET="$1"
[ -r "$TARGET" ] || { echo "File not readable: $TARGET" >&2; exit 2; }

VIOLATIONS=0

# 一時ファイルは並列実行衝突回避 + 自動 cleanup
TMPDIR_LINT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LINT"' EXIT

# ---------- 検出ヘルパ ----------

# 違反パターンが「ある」とき FAIL
fail_if_match() {
  local name="$1"
  local pattern="$2"
  local message="$3"
  local match
  set +e
  match=$(grep -nE -e "$pattern" -- "$TARGET" 2>/dev/null)
  local rc=$?
  set -e
  if [ $rc -ge 2 ]; then
    printf '\033[31m[ERROR]\033[0m %s — grep failure (rc=%s)\n' "$name" "$rc" >&2
    exit 2
  fi
  if [ $rc -eq 0 ] && [ -n "$match" ]; then
    printf '\033[31m[FAIL]\033[0m %s\n' "$name"
    printf '       %s\n' "$message"
    while IFS= read -r line; do printf '       %s\n' "$line"; done <<< "$match"
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    printf '\033[32m[PASS]\033[0m %s\n' "$name"
  fi
}

# 「実行コマンド行に command があるが必須オプションが欠落」のとき FAIL
# 検出対象: 行頭 (空白 / `$` プロンプト / env assignment / command substitution の後) からコマンドが始まる行
# 除外対象: markdown 内の inline code (`...` で囲まれた言及) / 文中の言及 / 行内の `#` 以降のコメント
# rc=2 (regex error) は即 exit 2
fail_if_command_missing_option() {
  local name="$1"
  local command_pattern="$2"  # 行頭から command が始まるかの ERE (caret 込みで指定)
  local required_pattern="$3" # 同じ行に必須 option があるかの ERE
  local message="$4"
  local violations_local=()
  local lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # 未クォート `#` 以降を除外 (簡易) — `'foo # bar'` `"foo # bar"` 内の # は除外しないので不完全だが実用上は十分
    local stripped="${line%%#*}"
    set +e
    printf '%s' "$line" | grep -qE -e "$command_pattern"
    local cmd_rc=$?
    if [ $cmd_rc -ge 2 ]; then
      printf '\033[31m[ERROR]\033[0m %s — command grep failure (rc=%s)\n' "$name" "$cmd_rc" >&2
      set -e
      exit 2
    fi
    if [ $cmd_rc -eq 0 ]; then
      printf '%s' "$stripped" | grep -qE -e "$required_pattern"
      local req_rc=$?
      if [ $req_rc -ge 2 ]; then
        printf '\033[31m[ERROR]\033[0m %s — required grep failure (rc=%s)\n' "$name" "$req_rc" >&2
        set -e
        exit 2
      fi
      if [ $req_rc -ne 0 ]; then
        violations_local+=("${lineno}: ${line}")
      fi
    fi
    set -e
  done < "$TARGET"
  if [ ${#violations_local[@]} -gt 0 ]; then
    printf '\033[31m[FAIL]\033[0m %s\n' "$name"
    printf '       %s\n' "$message"
    for v in "${violations_local[@]}"; do printf '       %s\n' "$v"; done
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    printf '\033[32m[PASS]\033[0m %s\n' "$name"
  fi
}

echo "=== 環境系 lint 自動チェック (14 項目中 10 系統) ==="
echo "対象: $TARGET"
echo

# ---------- 検出ルール ----------

# #1. BSD sed / grep 互換: \s \t \d (PCRE 依存) + grep -P 自体も NG
fail_if_match "#1. BSD sed / grep 互換 (\\\\s / \\\\t / \\\\d 不使用 + grep -P NG)" \
  '(sed|grep)([[:space:]]|[^|]*)[^|]*\\[std]([^|]|$)|grep([[:space:]]|[^|]*)-P([[:space:]]|$)' \
  '\\s \\t \\d は PCRE 依存 / grep -P も BSD 非対応。[[:space:]] [0-9] [[:digit:]] と grep -E を使用'

# #2. BSD sed -i: 推奨は sed -i.bak (両対応 / canonical)
# canonical PASS 形: sed -i.<ext> (拡張子と空白なしで連結)
# NG: sed -i (GNU 専用) / sed -i '' (BSD 専用) / sed -i .bak (space 区切り) / sed -i'' (空文字)
fail_if_match "#2. sed -i は -i.bak 形式 canonical (両対応 / GNU 専用 / BSD 専用 / space 区切り NG)" \
  "(^|[^[:alnum:]])sed[[:space:]]+-i([[:space:]]+([^.[:space:]]|$|'')|''([[:space:]]|$))" \
  'sed -i 直後に「.<拡張子>」を空白なしで連結する canonical を採用。sed -i.bak ... && rm -f file.bak'

# #3. zsh nomatch: *.{...,...} (大文字小文字 / 拡張子 . 含む全パターン)
fail_if_match "#3. zsh brace 展開を避ける" \
  '\*\.\{[^}]+,[^}]+\}' \
  '*.{ts,tsx} 系は zsh の nomatch エラー。find . -maxdepth 1 \( -name "*.ts" -o -name "*.tsx" \) を推奨'

# #4. git diff: 動く ref (main / origin/main / HEAD~ / branch名 / space 区切り 2 refs) との比較
# 例外: rev-parse 等で固定 SHA を取得した変数を含む行は許容
fail_if_match "#4. git diff の base/target は動く ref を避け SHA 固定" \
  'git[[:space:]]+diff([[:space:]]+--?[a-zA-Z-]+(=[^[:space:]]+)?)*[[:space:]]+([a-zA-Z][^.[:space:]]*\.\.[a-zA-Z]|[a-zA-Z][^[:space:]]*\.\.HEAD|HEAD([~^][[:digit:]]+)?\.\.HEAD|HEAD[[:space:]]+[a-zA-Z]|main[[:space:]]+HEAD|origin/[a-zA-Z][^[:space:]]*[[:space:]]+HEAD)' \
  '動く ref (main..HEAD / HEAD~1..HEAD / git diff main HEAD 等) は時間で変わる。BASE_SHA / TARGET_SHA を rev-parse で固定し、git diff "$BASE_SHA..$TARGET_SHA" を推奨'

# 行頭実行コマンドの prefix: 空白 / $ / # / env 変数代入 / command substitution 内
# 例: `npm run dev` / `$ npm run dev` / `# npm run dev` / `NODE_ENV=foo npm run dev` / `HTTP_CODE=$(curl ...)`
EXEC_PREFIX='^[[:space:]]*([$#][[:space:]]+)?(([A-Z][A-Z0-9_]*=[^[:space:]]*[[:space:]]+)*|env[[:space:]]+([A-Z][A-Z0-9_]*=[^[:space:]]*[[:space:]]+)+|[A-Z][A-Z0-9_]+=\$\([[:space:]]*)?'

# #5. port pin: npm run dev (PORT pin / --port なし)
fail_if_command_missing_option "#5. PORT pin (npm run dev に PORT 指定)" \
  "${EXEC_PREFIX}npm[[:space:]]+run[[:space:]]+dev([^[:alnum:]]|$)" \
  '(^|[[:space:]])PORT=|--port[[:space:]=]' \
  'PORT=XXXX npm run dev か --port XXXX で port pin する'

# #6. curl: -w "%{http_code}" / --write-out 必須 (status code 取得)
fail_if_command_missing_option "#6. curl で status code 取得 (-w / --write-out + %{http_code})" \
  "${EXEC_PREFIX}curl([[:space:]]|$)" \
  '(-w[[:space:]=]?[^[:space:]]*|--write-out[[:space:]=]?[^[:space:]]*)%\{http_code\}' \
  'curl で status code を %{http_code} で取得していない (-w や --write-out を使う)'

# #10. 秘密値の表示 / 漏洩パターン
# 検出対象: 行頭コマンドとしての (a) echo "$VAR" / "KEY=$VAR" / (b) cat .env* / (c) printenv / (d) env (assignment なし)
# 除外: printf '%s' "$VAR" | (vercel|op|aws|gcloud) は #11 推奨形なので除外
fail_if_match "#10. 秘密値を echo / 表示しない (cat .env / printenv / env)" \
  '^[[:space:]]*([$#][[:space:]]+)?(echo[[:space:]]+("[^"]*\$[A-Z_]|[A-Z][A-Z0-9_]*=\$)|cat[[:space:]]+\.env|printenv([[:space:]]|$)|env[[:space:]]*$)' \
  'echo "$VAR" / echo "KEY=$VAR" / cat .env* / printenv / env (引数なし) は秘密値漏洩リスク。[ -n "$VAR" ] で有無判定 / printf '\''%s'\'' "$VALUE" | <env コマンド> で投入'

# #11. env 投入は printf %s (echo NG / printf %s OK)
fail_if_match "#11. env 投入は printf %s (echo 末尾改行混入回避)" \
  '^[[:space:]]*([$#][[:space:]]+)?echo[[:space:]]+"\$[A-Z_][A-Z0-9_]*"[[:space:]]*\|[[:space:]]*(vercel|op|aws|gcloud)' \
  'echo は末尾に \\n を付与してキー破損。printf '\''%s'\'' "$VALUE" | <env コマンド> を使用'

# #12. codex は -s read-only (sandbox 明示)
fail_if_command_missing_option "#12. codex exec / review は -s read-only で投入" \
  "${EXEC_PREFIX}codex[[:space:]]+(exec|review)([[:space:]]|$)" \
  '(-s[[:space:]=]+read-only|--sandbox[[:space:]=]+read-only)' \
  'codex 実行時に -s read-only / --sandbox read-only が明示されていない (書き込み許可で監査すると差分汚染)'

# #14. cwd 絶対パス: cd / git -C の引数が許可 prefix 以外を FAIL
# 許可: /abs / $HOME / ${HOME} / $PWD / ${PWD} / "$HOME/..." / "/abs"
# NG: cd ./repo / cd ../repo / cd ~/repo / cd repo / git -C "./repo" / git -C "$PROJECT_DIR" (任意変数)
fail_if_match '#14. cd / git -C は絶対パス ($HOME / $PWD / /abs 以外 NG)' \
  '(^|[^[:alnum:]])(cd|git[[:space:]]+-C)[[:space:]]+("?(\.{1,2}/|~/|[a-zA-Z][a-zA-Z0-9_./-]*[a-zA-Z0-9])"?|"?\$\{?[A-Z][A-Z0-9_]*\}?(/|"?$))' \
  '相対パス / ~/ / 任意変数禁止。/abs/path or "$HOME/..." or "$PWD/..." を使用 (~/foo は quote 内で展開されないため避ける)'

echo
if [ "$VIOLATIONS" -eq 0 ]; then
  printf '\033[32m✅ 自動チェック PASS。残り 4 項目 (#7 next-env.d.ts gitignore / #8 dotenv 4 ファイル / #9 .env.local tracked / #13 heredoc quoted) は目視確認してください\033[0m\n'
  exit 0
else
  printf '\033[31m❌ %d 項目で違反検出 — 修正してください\033[0m\n' "$VIOLATIONS"
  exit 1
fi
