#!/usr/bin/env bash
# tools/audit-state-init.sh — Multi-repo Phase 監査ループの state.json 初期化
#
# claude-codex-audit-toolkit v0.5-nextjs-supabase の docs/10 で定義した
# state.json schema を ~/audit-multi-repo-state.json に初期化する。
#
# Usage:
#   ./tools/audit-state-init.sh
#
# 既存の state.json があれば backup (.bak) を作って上書き。

set -euo pipefail

STATE_FILE="${HOME}/audit-multi-repo-state.json"
BACKUP_FILE="${HOME}/audit-multi-repo-state.json.bak.$(date +%Y%m%d-%H%M%S)"

if [ -f "$STATE_FILE" ]; then
  cp "$STATE_FILE" "$BACKUP_FILE"
  printf 'Existing state backed up to: %s\n' "$BACKUP_FILE"
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$STATE_FILE" <<EOF
{
  "version": "1.0",
  "started_at": "${NOW}",
  "last_updated_at": "${NOW}",
  "config": {
    "max_rounds_per_phase": 3,
    "per_round_timeout_sec": 600,
    "global_concurrent_repos": 3,
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
      "aifcc-cpn": "https://cpn.aifcc.jp/"
    }
  },
  "repos": {
    "aifcc-workshop": {
      "path": "/Users/5dmgmt/Plugins/aifcc-workshop",
      "current_focus": null,
      "phase_total": 75,
      "phase_total_done": 0,
      "courses": {},
      "summary": {
        "all_pass_count": 0,
        "scope_cut_count": 0,
        "aborted_count": 0,
        "error_count": 0,
        "critical_count": 0,
        "total_commits": 0,
        "total_duration_sec": 0
      },
      "paused": false
    },
    "aifcc-run": {
      "path": "/Users/5dmgmt/Plugins/aifcc-run",
      "current_focus": null,
      "phase_total": 50,
      "phase_total_done": 0,
      "courses": {},
      "summary": {
        "all_pass_count": 0,
        "scope_cut_count": 0,
        "aborted_count": 0,
        "error_count": 0,
        "critical_count": 0,
        "total_commits": 0,
        "total_duration_sec": 0
      },
      "paused": false
    },
    "aifcc-cpn": {
      "path": "/Users/5dmgmt/Plugins/aifcc-cpn",
      "current_focus": null,
      "phase_total": 313,
      "phase_total_done": 0,
      "courses": {},
      "summary": {
        "all_pass_count": 0,
        "scope_cut_count": 0,
        "aborted_count": 0,
        "error_count": 0,
        "critical_count": 0,
        "total_commits": 0,
        "total_duration_sec": 0
      },
      "paused": false
    }
  },
  "global_summary": {
    "consecutive_abort": 0,
    "consecutive_build_failure": 0,
    "consecutive_frozen_recidive": 0
  },
  "paused": false,
  "stop_reason": null
}
EOF

printf 'state.json initialized at: %s\n' "$STATE_FILE"
printf 'Phase totals: Workshop=75 / RUN=50 / CPN=313 (約 450 Phase)\n'
printf '\n'
printf 'Next steps:\n'
printf '  1. tools/multi-repo-audit-agent.sh skeleton 実装 (docs/10 Step 4-7)\n'
printf '  2. tools/audit-claim-and-fix-subagent.md template 作成\n'
printf '  3. tools/audit-smoke-test.sh 実装\n'
printf '  4. dry-run (Step 8)\n'
printf '\n'
printf 'Resume guide: cat tools/RESUME-AUDIT-LOOP.md\n'
