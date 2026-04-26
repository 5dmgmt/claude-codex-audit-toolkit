#!/usr/bin/env bash
#
# Codex 監査プロンプト生成スクリプト
#
# 使い方:
#   ./scripts/codex-audit-prompt-gen.sh \
#     --runbook docs/runbooks/foo.md \
#     --round R3 \
#     --prev-findings "P2x5 / P3x1 反映済" \
#     --expected "5-15 件"
#
# 出力: 標準出力に展開済プロンプト
# 直接 codex に渡す例:
#   ./scripts/codex-audit-prompt-gen.sh ... | codex exec -s read-only -m gpt-5.5 -c model_reasoning_effort="xhigh"
#

set -euo pipefail

# --- 引数パース ---
RUNBOOK_PATH=""
ROUND_NUM="R1"
PREV_FINDINGS="初回"
EXPECTED_COUNT="5-30 件"
TEMPLATE_PATH="$(cd "$(dirname "$0")/.." && pwd)/docs/07-runbook-templates/codex-audit-prompt.txt"

while [ $# -gt 0 ]; do
  case "$1" in
    --runbook)        RUNBOOK_PATH="$2";        shift 2 ;;
    --round)          ROUND_NUM="$2";           shift 2 ;;
    --prev-findings)  PREV_FINDINGS="$2";       shift 2 ;;
    --expected)       EXPECTED_COUNT="$2";      shift 2 ;;
    --template)       TEMPLATE_PATH="$2";       shift 2 ;;
    -h|--help)
      sed -n '3,18p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# --- 必須変数 verify (独立ブロック / fail-fast) ---
: "${RUNBOOK_PATH:?--runbook is required}"
[ -f "$RUNBOOK_PATH" ] || { echo "Runbook not found: $RUNBOOK_PATH" >&2; exit 1; }
[ -f "$TEMPLATE_PATH" ] || { echo "Template not found: $TEMPLATE_PATH" >&2; exit 1; }

# --- commit SHA を確実に取得 ---
TARGET_SHA=$(git rev-parse --short HEAD 2>/dev/null) || {
  echo "Not a git repository or HEAD unset" >&2
  exit 1
}

# --- placeholder 置換 ---
PROMPT=$(cat "$TEMPLATE_PATH")
PROMPT="${PROMPT//__SHA__/$TARGET_SHA}"
PROMPT="${PROMPT//__RUNBOOK_PATH__/$RUNBOOK_PATH}"
PROMPT="${PROMPT//__ROUND_NUM__/$ROUND_NUM}"
PROMPT="${PROMPT//__PREV_FINDINGS__/$PREV_FINDINGS}"
PROMPT="${PROMPT//__EXPECTED_COUNT__/$EXPECTED_COUNT}"

printf '%s\n' "$PROMPT"
