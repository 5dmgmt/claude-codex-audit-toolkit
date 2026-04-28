#!/usr/bin/env bash
# tools/phase-audit-agent.sh — Phase 監査エージェントループ prototype v0.1
#
# claude-codex-audit-toolkit v0.5-nextjs-supabase の docs/09 Step 2 prototype。
# 1 Phase = 1 ファイル を Codex で R1-R5 監査、ALL PASS or scope cut まで自走。
# v0.1 では「監査ループ + 判定」のみ。P1 finding 反映 (Claude Code subagent ハンドオフ) は v0.2。
#
# Usage:
#   TARGET_REPO=/Users/5dmgmt/Plugins/aifcc-workshop \
#   PHASE_FILE=app/workshop/data/phases/course1/phase10101.ts \
#   PHASE_ID=10101 \
#   RUNBOOK_FILE=AUDIT_RUNBOOK.md \
#   ./tools/phase-audit-agent.sh
#
# Env:
#   TARGET_REPO     監査対象リポの絶対パス (必須)
#   PHASE_FILE      監査対象 Phase ファイルの相対パス (必須)
#   PHASE_ID        Phase ID 数字 (必須 / 例 10101)
#   RUNBOOK_FILE    監査運用ガイドの相対パス (デフォルト: AUDIT_RUNBOOK.md)
#   MAX_ROUNDS      最大ラウンド数 (デフォルト: 5)
#   TIMEOUT_SEC     1 ラウンド timeout 秒 (デフォルト: 600)
#   MODEL           Codex model (デフォルト: gpt-5.5)
#   REASONING       reasoning effort (デフォルト: xhigh)

set -euo pipefail

# ============================================================
# Config
# ============================================================
: "${TARGET_REPO:?TARGET_REPO is required (例: /Users/5dmgmt/Plugins/aifcc-workshop)}"
: "${PHASE_FILE:?PHASE_FILE is required (例: app/workshop/data/phases/course1/phase10101.ts)}"
: "${PHASE_ID:?PHASE_ID is required (例: 10101)}"
RUNBOOK_FILE="${RUNBOOK_FILE:-AUDIT_RUNBOOK.md}"
MAX_ROUNDS="${MAX_ROUNDS:-5}"
TIMEOUT_SEC="${TIMEOUT_SEC:-600}"
MODEL="${MODEL:-gpt-5.5}"
REASONING="${REASONING:-xhigh}"

# ============================================================
# Validation
# ============================================================
[ -d "$TARGET_REPO" ] || { printf 'FAIL: TARGET_REPO does not exist: %s\n' "$TARGET_REPO"; exit 1; }
cd "$TARGET_REPO"

# git status check (本リポ Fix 1 の dirty fail-fast / untracked AUDIT_RUNBOOK.md は許容)
DIRTY=$(git status --porcelain=v1 --untracked-files=no 2>&1)
if [ -n "$DIRTY" ]; then
  printf 'WARN: dirty tree detected (modified files exist):\n%s\n' "$DIRTY" >&2
  printf '       continue でも良いが、commit pin の純度が落ちるので推奨は clean tree\n' >&2
fi

[ -f "$PHASE_FILE" ] || { printf 'FAIL: PHASE_FILE not found: %s\n' "$PHASE_FILE"; exit 1; }
[ -f "$RUNBOOK_FILE" ] || { printf 'FAIL: RUNBOOK_FILE not found: %s (作成してから本スクリプトを起動)\n' "$RUNBOOK_FILE"; exit 1; }

command -v codex >/dev/null || { printf 'FAIL: codex CLI not found (npm install -g @openai/codex)\n'; exit 1; }
command -v timeout >/dev/null || { printf 'FAIL: timeout command not found (brew install coreutils for gtimeout)\n'; exit 1; }

TARGET_SHA=$(git rev-parse HEAD)

# ============================================================
# Banner
# ============================================================
printf '=== Phase Audit Agent Loop v0.1 ===\n'
printf 'TARGET_REPO:  %s\n' "$TARGET_REPO"
printf 'PHASE_FILE:   %s\n' "$PHASE_FILE"
printf 'PHASE_ID:     %s\n' "$PHASE_ID"
printf 'RUNBOOK_FILE: %s\n' "$RUNBOOK_FILE"
printf 'TARGET_SHA:   %s\n' "$TARGET_SHA"
printf 'MAX_ROUNDS:   %s\n' "$MAX_ROUNDS"
printf 'TIMEOUT_SEC:  %s\n' "$TIMEOUT_SEC"
printf 'MODEL:        %s (%s)\n' "$MODEL" "$REASONING"
printf '\n'

# ============================================================
# Per-round loop
# ============================================================
round=1
prev_total=-1
stagnation_count=0
status="running"
declare -a round_results

while [ "$round" -le "$MAX_ROUNDS" ]; do
  printf '=== Round %d / %d ===\n' "$round" "$MAX_ROUNDS"

  ROUND_OUTPUT="/tmp/phase-${PHASE_ID}-r${round}.md"
  ROUND_LOG="/tmp/phase-${PHASE_ID}-r${round}.log"

  PROMPT="${RUNBOOK_FILE} を読み、commit ${TARGET_SHA} の snapshot として Phase ${PHASE_ID} (file: ${PHASE_FILE}) の R${round} 監査。Fix 6 横断 6 観点 ULTRATHINK を Next.js + Supabase 文脈で適用。Critical/High/Medium/Low に分類。Critical/High が無ければ明示。"

  if ! timeout "$TIMEOUT_SEC" codex exec -s read-only -m "$MODEL" -c "model_reasoning_effort=$REASONING" \
    --skip-git-repo-check \
    --output-last-message "$ROUND_OUTPUT" \
    "$PROMPT" < /dev/null > "$ROUND_LOG" 2>&1; then
    printf 'FAIL: Codex timeout or error at round %d (log: %s)\n' "$round" "$ROUND_LOG"
    status="timeout_aborted"
    break
  fi

  if [ ! -f "$ROUND_OUTPUT" ]; then
    printf 'FAIL: %s not created (Codex did not emit final message)\n' "$ROUND_OUTPUT"
    status="codex_no_output"
    break
  fi

  JUDGMENT=$(grep -E '総合判定' "$ROUND_OUTPUT" | tail -1)
  printf '判定: %s\n' "$JUDGMENT"

  if echo "$JUDGMENT" | grep -q 'ALL PASS'; then
    printf 'ALL PASS at round %d\n' "$round"
    status="all_pass"
    round_results+=("R${round}: ALL PASS")
    break
  fi

  # 件数抽出 (P1/P2/P3 形式と Critical/High/Medium/Low 形式の両方に対応)
  P1=$(echo "$JUDGMENT" | grep -oE '(P1|Critical)×[0-9]+' | grep -oE '[0-9]+' | head -1 || printf '0')
  P2=$(echo "$JUDGMENT" | grep -oE '(P2|High)×[0-9]+' | grep -oE '[0-9]+' | head -1 || printf '0')
  P3=$(echo "$JUDGMENT" | grep -oE '(P3|Medium)×[0-9]+' | grep -oE '[0-9]+' | head -1 || printf '0')
  P4=$(echo "$JUDGMENT" | grep -oE 'Low×[0-9]+' | grep -oE '[0-9]+' | head -1 || printf '0')
  TOTAL=$((P1 + P2 + P3 + P4))
  round_results+=("R${round}: P1=${P1} P2=${P2} P3=${P3} Low=${P4} Total=${TOTAL}")
  printf 'Round %d: P1=%d P2=%d P3=%d Low=%d Total=%d\n' "$round" "$P1" "$P2" "$P3" "$P4" "$TOTAL"

  # 停滞判定 (前ラウンド同数なら scope_cut 候補)
  if [ "$prev_total" -ge 0 ] && [ "$TOTAL" -eq "$prev_total" ]; then
    stagnation_count=$((stagnation_count + 1))
    if [ "$stagnation_count" -ge 2 ]; then
      printf 'Scope cut: 件数停滞 2 連続 (= %d)\n' "$TOTAL"
      status="scope_cut_stagnation"
      break
    fi
  else
    stagnation_count=0
  fi
  prev_total="$TOTAL"

  # P1 = 0 の場合、人間判断のため一旦止める (P2/P3 は反映するか保留するか判断要)
  if [ "$P1" -eq 0 ]; then
    printf 'P1=0 reached at round %d, exit loop (残 P2=%d P3=%d Low=%d は人間判断)\n' "$round" "$P2" "$P3" "$P4"
    status="p1_clean"
    break
  fi

  # v0.1: subagent ハンドオフは未実装 (= 人間が P1 を反映してから次 round)
  printf '\n'
  printf '=== Round %d P1=%d finding を反映してから次 round 起動 (v0.1) ===\n' "$round" "$P1"
  printf '   1. ROUND_OUTPUT: %s を確認\n' "$ROUND_OUTPUT"
  printf '   2. P1 finding を Claude Code or 手動で反映 (1 違和感 = 1 commit)\n'
  printf '   3. type-check + lint + build → main 直 push\n'
  printf '   4. %s 末尾に R%d 反映済セクションを追記\n' "$RUNBOOK_FILE" "$round"
  printf '   5. 本スクリプトを再起動 (v0.2 で自動化予定)\n'
  printf '\n'
  status="awaiting_human_reflection"
  break
done

if [ "$round" -gt "$MAX_ROUNDS" ]; then
  status="scope_cut_max_rounds"
fi

# ============================================================
# 結果出力
# ============================================================
printf '\n'
printf '=== Final Status: %s ===\n' "$status"
printf 'Round count: %d / %d\n' "$round" "$MAX_ROUNDS"
printf 'Round results:\n'
for r in "${round_results[@]}"; do
  printf '  %s\n' "$r"
done
printf 'Output dir: /tmp/phase-%s-r*.md\n' "$PHASE_ID"
printf '\n'

# ============================================================
# 終了 status code
# ============================================================
case "$status" in
  all_pass)               exit 0 ;;
  p1_clean)               exit 0 ;;
  awaiting_human_reflection) exit 2 ;;  # 反映待ち
  scope_cut_*)            exit 3 ;;
  timeout_aborted)        exit 124 ;;   # GNU timeout 互換
  codex_no_output)        exit 4 ;;
  *)                      exit 1 ;;
esac
