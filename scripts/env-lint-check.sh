#!/usr/bin/env bash
#
# 環境系 lint 自動チェックスクリプト
#
# docs/05-env-lint-checklist.md の 14 項目のうち、機械検出に向く 10 系統を
# grep ベースで自動チェックする。残り 4 項目 (#7 next-env.d.ts gitignore /
# #8 dotenv 4 load slot + 6 表記 / #9 .env.local commit 禁止 / #13 heredoc quoted) は
# 目視確認が必要。詳細は docs/05 を参照。
# #5/#7/#8/#9 は Next.js / Node.js adapter 固有なので、非該当の場合は N/A 記録で可。
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

# 違反パターンが「ある」とき FAIL — 行頭 # コメント除外、行内 # 以降除外
fail_if_match() {
  local name="$1"
  local pattern="$2"
  local message="$3"
  local violations_local=()
  local lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    case "$line" in \#*) continue ;; esac
    local stripped="${line%%#*}"
    set +e
    printf '%s' "$stripped" | grep -qE -e "$pattern"
    local rc=$?
    set -e
    if [ $rc -ge 2 ]; then
      printf '\033[31m[ERROR]\033[0m %s — grep failure (rc=%s)\n' "$name" "$rc" >&2
      exit 2
    fi
    if [ $rc -eq 0 ]; then
      violations_local+=("${lineno}: ${line}")
    fi
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
# 専用関数で token 単位に検査 (regex の限界を回避)
check_sed_inplace() {
  local name="#2. sed -i は -i.bak 形式 canonical (両対応 / GNU 専用 / BSD 専用 / space 区切り NG)"
  local message='sed -i 直後に「.<拡張子>」を空白なしで連結する canonical を採用。sed -i.bak ... && rm -f file.bak'
  local violations_local=()
  local lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    case "$line" in \#*) continue ;; esac
    local stripped="${line%%#*}"
    # `sed -i<X>` の <X> を抽出 (単一空白後の token または直結 token)
    if [[ "$stripped" =~ (^|[^[:alnum:]])sed[[:space:]]+(-i[^[:space:]]*) ]]; then
      local arg="${BASH_REMATCH[2]}"
      case "$arg" in
        -i.[!.\ ]*)
          : # PASS: -i.<ext>
          ;;
        *)
          violations_local+=("${lineno}: ${line}    [arg='${arg}']")
          ;;
      esac
    elif [[ "$stripped" =~ (^|[^[:alnum:]])sed[[:space:]]+-i[[:space:]]+ ]]; then
      # `sed -i ` の後に space 区切り arg が来るパターン (NG: BSD 専用 '' / space 区切り .bak)
      violations_local+=("${lineno}: ${line}    [space 区切りまたは空文字 -i]")
    fi
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
check_sed_inplace

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
# 行頭実行コマンドの prefix: 空白 / $ プロンプト / env 変数代入 / quoted/unquoted command substitution
# 例: `npm run dev` / `$ npm run dev` / `NODE_ENV=foo npm run dev` / `HTTP_CODE=$(curl ...)` / `HTTP_CODE="$(curl ...)"`
# 注: `# ` プロンプトは markdown 内の他形式と紛らわしいため受け付けない
EXEC_PREFIX='^[[:space:]]*(\$[[:space:]]+)?(([A-Z][A-Z0-9_]*=[^[:space:]]*[[:space:]]+)*|env[[:space:]]+([A-Z][A-Z0-9_]*=[^[:space:]]*[[:space:]]+)+|[A-Z][A-Z0-9_]+="?\$\([[:space:]]*)?'

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
# 検出対象: 行頭コマンドとしての (a) echo (option 付き含む) $VAR / "$VAR" / "${VAR}" / "KEY=$VAR" / "KEY=${VAR}" / (b) cat .env* / (c) printenv / (d) env (引数なし or pipe)
# 除外: printf '%s' "$VAR" | (vercel|op|aws|gcloud) は #11 推奨形なので除外 (#10b で別途扱う)
fail_if_match "#10. 秘密値を echo / 表示しない (echo option 付き / cat .env / printenv / env / braced 変数も検出)" \
  '^[[:space:]]*\$?[[:space:]]*(echo([[:space:]]+-[a-zA-Z]+)?[[:space:]]+([^|]*[\"]?[A-Z][A-Z0-9_]*=)?[\"]?\$\{?[A-Z_][A-Z0-9_]*\}?|cat[[:space:]]+\.env|printenv([[:space:]]|$)|env[[:space:]]*(\||$|>))' \
  'echo $VAR (option 含む) / cat .env* / printenv / env (引数なし) は秘密値漏洩リスク。[ -n "$VAR" ] で有無判定 / printf '\''%s'\'' "$VALUE" | <env コマンド> で投入'

# #10b. printf による秘密値の stdout 出力 (許可形 printf '%s' "$VAR" | <env コマンド> 以外は FAIL)
# 検出: 行頭 printf に $VAR / ${VAR} を含み、行内に pipe (|) が無い (= stdout 直出力) 行
# 除外: pipe で env コマンドに渡す形 (#11 推奨形)
fail_if_match "#10b. printf による秘密値の stdout 出力 (printf '%s' \"\$VAR\" | <env コマンド> 以外は FAIL)" \
  '^[[:space:]]*\$?[[:space:]]*printf[[:space:]]+[^|]*\$\{?[A-Z_][A-Z0-9_]*\}?[^|]*$' \
  'printf $VAR の stdout 直接出力は秘密値漏洩リスク。許可形は printf '\''%s'\'' "$VALUE" | (vercel|op|aws|gcloud) のみ'

# #11. env 投入は printf %s (echo NG / printf %s OK)
# braced 変数 ${VAR} も検出
fail_if_match "#11. env 投入は printf %s (echo 末尾改行混入回避 / braced 変数も検出)" \
  '^[[:space:]]*\$?[[:space:]]*echo[[:space:]]+["]?\$\{?[A-Z_][A-Z0-9_]*\}?["]?[[:space:]]*\|[[:space:]]*(vercel|op|aws|gcloud)' \
  'echo は末尾に \\n を付与してキー破損。printf '\''%s'\'' "$VALUE" | <env コマンド> を使用'

# #12. codex は -s read-only (sandbox 明示)
fail_if_command_missing_option "#12. codex exec / review は -s read-only で投入" \
  "${EXEC_PREFIX}codex[[:space:]]+(exec|review)([[:space:]]|$)" \
  '(-s[[:space:]=]+read-only|--sandbox[[:space:]=]+read-only)' \
  'codex 実行時に -s read-only / --sandbox read-only が明示されていない (書き込み許可で監査すると差分汚染)'

# #14. cwd 絶対パス: cd / git -C の引数が許可 prefix 以外を FAIL (allowlist 方式)
# 許可: /abs / $HOME / ${HOME} / $PWD / ${PWD} (quote 有無問わず)
# NG: cd ./repo / cd ../repo / cd ~/repo / cd repo / git -C "./repo" / git -C "$PROJECT_DIR" (任意変数)
check_cwd_allowlist() {
  local name='#14. cd / git -C は絶対パス ($HOME / $PWD / /abs 以外 NG)'
  local message='相対パス / ~/ / $HOME・$PWD 以外の変数禁止。/abs/path or "$HOME/..." or "$PWD/..." を使用'
  local violations_local=()
  local lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    case "$line" in \#*) continue ;; esac
    local stripped="${line%%#*}"

    # cd / git -C の各引数を抽出 (簡易: 各出現で 1 つ目の引数のみ)
    local rest="$stripped"
    while [[ "$rest" =~ (^|[^[:alnum:]])(cd|git[[:space:]]+-C)[[:space:]]+([^[:space:]]+) ]]; do
      local arg="${BASH_REMATCH[3]}"
      rest="${rest#*${BASH_REMATCH[0]}}"
      # quote 剥がし
      arg="${arg#\"}"
      arg="${arg%\"}"
      arg="${arg#\'}"
      arg="${arg%\'}"
      # allowlist 判定
      case "$arg" in
        /*|\$HOME|\$HOME/*|\$\{HOME\}|\$\{HOME\}/*|\$PWD|\$PWD/*|\$\{PWD\}|\$\{PWD\}/*)
          : # 許可
          ;;
        *)
          violations_local+=("${lineno}: ${line}    [arg='${arg}']")
          ;;
      esac
    done
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
check_cwd_allowlist

echo
if [ "$VIOLATIONS" -eq 0 ]; then
  printf '\033[32m✅ 自動チェック PASS。残り 4 項目を目視確認: #7 next-env.d.ts gitignore (Next.js のみ / 非該当なら N/A) / #8 dotenv 4 load slot + 6 表記 (Next.js のみ / 非該当なら N/A) / #9 .env.local tracked (Next.js のみ / 非該当なら N/A) / #13 heredoc quoted (全プロジェクト)\033[0m\n'
  exit 0
else
  printf '\033[31m❌ %d 項目で違反検出 — 修正してください\033[0m\n' "$VIOLATIONS"
  exit 1
fi
