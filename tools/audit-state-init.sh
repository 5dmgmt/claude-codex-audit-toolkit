#!/usr/bin/env bash
# tools/audit-state-init.sh — Multi-repo Phase 監査ループの state.json 初期化 (4 repo / inventory 連動)
#
# claude-codex-audit-toolkit v0.5-nextjs-supabase の docs/10 で定義した state.json schema を
# ~/audit-multi-repo-state.json に初期化する。
#
# 実 inventory: tools/audit-phase-inventory.sh の出力を取り込む。
#   - Workshop: 165 phase
#   - RUN: 46 phase
#   - SIFT: 99 phase
#   - CPN: 15 course (1 ファイル = 1 監査単位 / v0.7+ で phase split 予定)
#   合計: 325 監査単位
#
# Usage:
#   ./tools/audit-state-init.sh
#
# 既存の state.json があれば backup (.bak.YYYYMMDD-HHMMSS) を作って上書き。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${HOME}/audit-multi-repo-state.json"
BACKUP_FILE="${HOME}/audit-multi-repo-state.json.bak.$(date +%Y%m%d-%H%M%S)"

if [ -f "$STATE_FILE" ]; then
  cp "$STATE_FILE" "$BACKUP_FILE"
  printf 'Existing state backed up to: %s\n' "$BACKUP_FILE"
fi

command -v jq >/dev/null || { printf 'FAIL: jq is required\n'; exit 1; }

# inventory を取得
INVENTORY=$("$SCRIPT_DIR/audit-phase-inventory.sh")

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 各 repo の phase 総数を計算
WS_TOTAL=$(echo "$INVENTORY" | jq '[.["aifcc-workshop"][] | keys | length] | add')
RUN_TOTAL=$(echo "$INVENTORY" | jq '[.["aifcc-run"][] | keys | length] | add')
SIFT_TOTAL=$(echo "$INVENTORY" | jq '[.["aifcc-sift"][] | keys | length] | add')
CPN_TOTAL=$(echo "$INVENTORY" | jq '[.["aifcc-cpn"][] | keys | length] | add')
GRAND=$((WS_TOTAL + RUN_TOTAL + SIFT_TOTAL + CPN_TOTAL))

# config / summary template
CONFIG=$(cat <<'EOF'
{
  "max_rounds_per_phase": 3,
  "per_round_timeout_sec": 600,
  "global_concurrent_repos": 4,
  "phase_cooldown_sec": 300,
  "model": "gpt-5.5",
  "fallback_model": "gpt-5.4",
  "reasoning_effort": "xhigh",
  "auto_commit": true,
  "auto_push": true,
  "stop_on_critical": true,
  "stop_on_consecutive_abort": 3,
  "stop_on_consecutive_build_failure": 5,
  "stop_on_consecutive_frozen_recidive": 3,
  "smoke_test_url": {
    "aifcc-workshop": "https://workshop.aifcc.jp/",
    "aifcc-run": "https://run.aifcc.jp/",
    "aifcc-sift": "https://sift.aifcc.jp/",
    "aifcc-cpn": "https://cpn.aifcc.jp/"
  }
}
EOF
)

EMPTY_SUMMARY='{"all_pass_count":0,"scope_cut_count":0,"aborted_count":0,"error_count":0,"critical_count":0,"total_commits":0,"total_duration_sec":0}'

# 各 repo の構造を組み立て
WORKSHOP=$(echo "$INVENTORY" | jq --argjson sum "$EMPTY_SUMMARY" --argjson total "$WS_TOTAL" '{
  path: "/Users/5dmgmt/Plugins/aifcc-workshop",
  current_focus: null,
  phase_total: $total,
  phase_total_done: 0,
  courses: .["aifcc-workshop"],
  summary: $sum,
  paused: false
}')
RUN_J=$(echo "$INVENTORY" | jq --argjson sum "$EMPTY_SUMMARY" --argjson total "$RUN_TOTAL" '{
  path: "/Users/5dmgmt/Plugins/aifcc-run",
  current_focus: null,
  phase_total: $total,
  phase_total_done: 0,
  courses: .["aifcc-run"],
  summary: $sum,
  paused: false
}')
SIFT_J=$(echo "$INVENTORY" | jq --argjson sum "$EMPTY_SUMMARY" --argjson total "$SIFT_TOTAL" '{
  path: "/Users/5dmgmt/Plugins/aifcc-sift",
  current_focus: null,
  phase_total: $total,
  phase_total_done: 0,
  courses: .["aifcc-sift"],
  summary: $sum,
  paused: false
}')
CPN_J=$(echo "$INVENTORY" | jq --argjson sum "$EMPTY_SUMMARY" --argjson total "$CPN_TOTAL" '{
  path: "/Users/5dmgmt/Plugins/aifcc-cpn",
  current_focus: null,
  phase_total: $total,
  phase_total_done: 0,
  courses: .["aifcc-cpn"],
  summary: $sum,
  paused: false
}')

jq -n \
  --arg now "$NOW" \
  --argjson config "$CONFIG" \
  --argjson workshop "$WORKSHOP" \
  --argjson run "$RUN_J" \
  --argjson sift "$SIFT_J" \
  --argjson cpn "$CPN_J" \
  '{
    version: "2.0",
    started_at: $now,
    last_updated_at: $now,
    config: $config,
    repos: {
      "aifcc-workshop": $workshop,
      "aifcc-run": $run,
      "aifcc-sift": $sift,
      "aifcc-cpn": $cpn
    },
    global_summary: {
      consecutive_abort: 0,
      consecutive_build_failure: 0,
      consecutive_frozen_recidive: 0
    },
    paused: false,
    stop_reason: null
  }' > "$STATE_FILE"

printf 'state.json initialized at: %s\n' "$STATE_FILE"
printf 'Phase totals: Workshop=%s / RUN=%s / SIFT=%s / CPN=%s = %s 監査単位\n' \
  "$WS_TOTAL" "$RUN_TOTAL" "$SIFT_TOTAL" "$CPN_TOTAL" "$GRAND"
printf '\n'
printf 'Next steps:\n'
printf '  1. tools/multi-repo-audit-agent.sh で scheduler 起動\n'
printf '  2. dry-run: ./tools/multi-repo-audit-agent.sh --dry-run --max-phases 5\n'
printf '  3. 本番: ./tools/multi-repo-audit-agent.sh\n'
printf '\n'
printf 'Resume guide: cat tools/RESUME-AUDIT-LOOP.md\n'
