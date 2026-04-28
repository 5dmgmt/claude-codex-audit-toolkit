#!/usr/bin/env bash
# tools/multi-repo-audit-agent.sh — Multi-repo Phase 監査エージェントループ scheduler
#
# claude-codex-audit-toolkit v0.5-nextjs-supabase / docs/10 設計の本体。
# Workshop / RUN / SIFT / CPN の 325 監査単位を 4 並列 + 同 repo 内 Phase 直列で自走監査する。
#
# Codex 監査 (per-Phase ループ) は phase-audit-agent.sh を再利用。
# Critical/High/Medium 反映 (subagent ハンドオフ) は audit-claim-and-fix-subagent.md template を使う。
# (本 skeleton 段階では subagent ハンドオフは echo placeholder / 実反映は v0.6 で Agent tool 連携)
#
# Usage:
#   ./tools/multi-repo-audit-agent.sh [options]
#
# Options:
#   --resume                  state.json の paused / status を尊重して再開
#   --dry-run                 Codex 監査は走らせず、scheduler ロジックのみ verify
#   --max-phases <N>          1 セッションで完走する最大 Phase 数 (デフォルト: 制限なし)
#   --only-repo <name>        指定 repo のみ実行 (例: aifcc-workshop)
#   --serial                  並列を無効化 (= 1 repo ずつ直列で実走)
#   --skip-smoke              smoke test を skip (dry-run 用)
#   --skip-cooldown           5 分 cooldown を skip (dry-run 用)
#   --no-fix                  反映 subagent を起動せず、監査のみ
#
# 終了 status:
#   0 — 全 Phase 完走 or paused (正常終了)
#   1 — 引数 / 環境エラー
#   2 — 致命停止 (Critical / build_instability / consecutive_abort 等)
#   3 — ユーザー停止 (Ctrl+C)

set -euo pipefail

# ============================================================
# Config
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="${HOME}/audit-multi-repo-state.json"
LOG_DIR="${HOME}/.audit-multi-repo-logs"
mkdir -p "$LOG_DIR"

# default flags
RESUME=false
DRY_RUN=false
MAX_PHASES=0  # 0 = unlimited
ONLY_REPO=""
SERIAL=false
SKIP_SMOKE=false
SKIP_COOLDOWN=false
NO_FIX=false

while [ $# -gt 0 ]; do
  case "$1" in
    --resume)         RESUME=true ;;
    --dry-run)        DRY_RUN=true; SKIP_SMOKE=true; SKIP_COOLDOWN=true; NO_FIX=true ;;
    --max-phases)     shift; MAX_PHASES="${1:-0}" ;;
    --only-repo)      shift; ONLY_REPO="${1:-}" ;;
    --serial)         SERIAL=true ;;
    --skip-smoke)     SKIP_SMOKE=true ;;
    --skip-cooldown)  SKIP_COOLDOWN=true ;;
    --no-fix)         NO_FIX=true ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

# ============================================================
# Validation
# ============================================================
[ -f "$STATE_FILE" ] || { printf 'FAIL: state.json not found at %s\n' "$STATE_FILE" >&2; printf '       run ./tools/audit-state-init.sh first\n' >&2; exit 1; }
command -v jq >/dev/null || { printf 'FAIL: jq is required\n' >&2; exit 1; }
command -v codex >/dev/null || $DRY_RUN || { printf 'FAIL: codex CLI not found (npm install -g @openai/codex)\n' >&2; exit 1; }
[ -x "$SCRIPT_DIR/phase-audit-agent.sh" ] || { printf 'FAIL: phase-audit-agent.sh not executable\n' >&2; exit 1; }

# ============================================================
# state.json 操作 helpers
# ============================================================
# state.json の排他 lock (4 worker 並列対応 / mkdir は atomic / portable)
STATE_LOCK_DIR="${HOME}/.audit-multi-repo-state.lock"
acquire_state_lock() {
  local waited=0
  while ! mkdir "$STATE_LOCK_DIR" 2>/dev/null; do
    sleep 0.05
    waited=$((waited + 1))
    if [ "$waited" -gt 600 ]; then
      printf 'state lock timeout (30s) — stale? rm -rf %s\n' "$STATE_LOCK_DIR" >&2
      rm -rf "$STATE_LOCK_DIR"
    fi
  done
}
release_state_lock() {
  rmdir "$STATE_LOCK_DIR" 2>/dev/null || true
}
trap 'release_state_lock' EXIT

state_get() {
  acquire_state_lock
  local result
  result=$(jq -r "$1" "$STATE_FILE")
  release_state_lock
  printf '%s\n' "$result"
}

state_update() {
  # 全引数を jq へ pass-through (最後の引数を filter として扱う)
  # macOS bash 3.2 互換のため eval / array slice は避ける
  local n=$#
  if [ "$n" -lt 1 ]; then
    printf 'state_update: need at least 1 arg (filter)\n' >&2
    return 1
  fi
  local i=1
  local args=()
  while [ "$i" -le "$n" ]; do
    args+=("${!i}")
    i=$((i + 1))
  done
  local last_index=$((n - 1))
  local jq_filter="${args[$last_index]}"
  unset "args[$last_index]"
  local tmp
  tmp=$(mktemp)
  acquire_state_lock
  jq "${args[@]+"${args[@]}"}" "$jq_filter" "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
  release_state_lock
}

state_set_paused() {
  local reason="${1:-user_request}"
  state_update --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" --arg reason "$reason" \
    '.paused = true | .stop_reason = $reason | .last_updated_at = $now'
}

# ============================================================
# Ctrl+C trap (安全停止)
# ============================================================
trap 'printf "\nINT received → paused: true\n" >&2; release_state_lock; state_set_paused "user_ctrl_c"; exit 3' INT TERM

# ============================================================
# Resume gate
# ============================================================
PAUSED=$(state_get '.paused')
STOP_REASON=$(state_get '.stop_reason')

if [ "$PAUSED" = "true" ]; then
  printf 'state.json paused=true / stop_reason=%s\n' "$STOP_REASON" >&2
  if [ "$RESUME" != "true" ]; then
    printf 'aborting. set paused=false manually OR pass --resume to ignore\n' >&2
    exit 1
  fi
  printf 'resuming despite paused=true (--resume passed)...\n' >&2
  state_update '.paused = false | .stop_reason = null'
fi

# ============================================================
# Banner
# ============================================================
printf '=== Multi-repo Phase Audit Scheduler v0.1 ===\n'
printf 'state:           %s\n' "$STATE_FILE"
printf 'log_dir:         %s\n' "$LOG_DIR"
printf 'dry_run:         %s\n' "$DRY_RUN"
printf 'max_phases:      %s\n' "${MAX_PHASES:-unlimited}"
printf 'only_repo:       %s\n' "${ONLY_REPO:-(all)}"
printf 'serial:          %s\n' "$SERIAL"
printf 'skip_smoke:      %s\n' "$SKIP_SMOKE"
printf 'skip_cooldown:   %s\n' "$SKIP_COOLDOWN"
printf 'no_fix:          %s\n' "$NO_FIX"
printf '\n'

# ============================================================
# Phase iterator (state.json から pending phase を取り出す)
# ============================================================
# 出力形式: <repo>\t<course>\t<phase_id>\t<file>
list_pending_phases() {
  local repo_filter="."
  if [ -n "$ONLY_REPO" ]; then
    repo_filter="select(.key == \"$ONLY_REPO\")"
  fi
  jq -r "
    .repos | to_entries | map($repo_filter) | .[] |
    .key as \$repo |
    .value.courses | to_entries | .[] |
    .key as \$course |
    .value | to_entries | .[] |
    select(.value.status == \"pending\" or .value.status == \"running\") |
    [\$repo, \$course, .key, .value.file] | @tsv
  " "$STATE_FILE"
}

# ============================================================
# Per-Phase 実行 (1 phase の監査 + 反映)
# ============================================================
run_phase() {
  local repo="$1"
  local course="$2"
  local phase_id="$3"
  local phase_file="$4"

  local repo_path
  repo_path=$(jq -r --arg r "$repo" '.repos[$r].path' "$STATE_FILE")
  local smoke_url
  smoke_url=$(jq -r --arg r "$repo" '.config.smoke_test_url[$r]' "$STATE_FILE")
  local model
  model=$(state_get '.config.model')
  local reasoning
  reasoning=$(state_get '.config.reasoning_effort')
  local timeout_sec
  timeout_sec=$(state_get '.config.per_round_timeout_sec')
  local max_rounds
  max_rounds=$(state_get '.config.max_rounds_per_phase')

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local phase_log="$LOG_DIR/${repo}-${course}-${phase_id}.log"

  printf '\n>>> [%s] %s/%s/%s (file=%s) <<<\n' "$now" "$repo" "$course" "$phase_id" "$phase_file"

  # Mark running
  state_update --arg r "$repo" --arg c "$course" --arg p "$phase_id" --arg now "$now" \
    '.repos[$r].courses[$c][$p].status = "running"
     | .repos[$r].courses[$c][$p].started_at //= $now
     | .repos[$r].current_focus = {course: $c, phase: $p, round: 1}
     | .last_updated_at = $now'

  if [ "$DRY_RUN" = "true" ]; then
    printf '  [dry-run] skipping codex audit\n'
    state_update --arg r "$repo" --arg c "$course" --arg p "$phase_id" --arg now "$now" \
      '.repos[$r].courses[$c][$p].status = "all_pass"
       | .repos[$r].courses[$c][$p].ended_at = $now
       | .repos[$r].phase_total_done += 1
       | .repos[$r].summary.all_pass_count += 1
       | .last_updated_at = $now'
    return 0
  fi

  # 実 codex 監査 → phase-audit-agent.sh 委任
  TARGET_REPO="$repo_path" \
  PHASE_FILE="$phase_file" \
  PHASE_ID="$phase_id" \
  RUNBOOK_FILE="AUDIT_RUNBOOK.md" \
  MAX_ROUNDS="$max_rounds" \
  TIMEOUT_SEC="$timeout_sec" \
  MODEL="$model" \
  REASONING="$reasoning" \
  bash "$SCRIPT_DIR/phase-audit-agent.sh" > "$phase_log" 2>&1 &
  local agent_pid=$!

  # 監査終了待ち + 結果取得
  wait "$agent_pid"
  local exit_code=$?

  local end_now
  end_now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # exit_code → status mapping (phase-audit-agent.sh の status code 仕様準拠)
  local final_status="error"
  case "$exit_code" in
    0) final_status="all_pass" ;;
    2) final_status="awaiting_human_reflection" ;;  # P1 finding 反映待ち
    3) final_status="scope_cut" ;;
    124) final_status="timeout_aborted" ;;
    4) final_status="codex_no_output" ;;
    *) final_status="error" ;;
  esac

  # state 更新
  local incr_field=""
  case "$final_status" in
    all_pass)                  incr_field="all_pass_count" ;;
    scope_cut)                 incr_field="scope_cut_count" ;;
    timeout_aborted|error)     incr_field="error_count" ;;
    awaiting_human_reflection) incr_field="aborted_count" ;;
    *)                         incr_field="error_count" ;;
  esac

  state_update --arg r "$repo" --arg c "$course" --arg p "$phase_id" \
    --arg now "$end_now" --arg status "$final_status" --arg incr "$incr_field" \
    '.repos[$r].courses[$c][$p].status = $status
     | .repos[$r].courses[$c][$p].ended_at = $now
     | .repos[$r].phase_total_done += 1
     | .repos[$r].summary[$incr] += 1
     | .last_updated_at = $now'

  printf '<<< %s/%s/%s → %s (log: %s) >>>\n' "$repo" "$course" "$phase_id" "$final_status" "$phase_log"

  # 致命停止判定: timeout_aborted / error の連続を check
  local consec_abort
  consec_abort=$(state_get '.global_summary.consecutive_abort')
  if [ "$final_status" = "timeout_aborted" ] || [ "$final_status" = "error" ]; then
    consec_abort=$((consec_abort + 1))
  else
    consec_abort=0
  fi
  state_update --arg n "$consec_abort" '.global_summary.consecutive_abort = ($n | tonumber)'

  local stop_threshold
  stop_threshold=$(state_get '.config.stop_on_consecutive_abort')
  if [ "$consec_abort" -ge "$stop_threshold" ]; then
    printf 'FATAL: consecutive_abort=%d >= %d → stop_all\n' "$consec_abort" "$stop_threshold" >&2
    state_set_paused "consecutive_abort"
    return 2
  fi

  # cooldown
  if [ "$SKIP_COOLDOWN" = "false" ]; then
    local cooldown
    cooldown=$(state_get '.config.phase_cooldown_sec')
    if [ "$cooldown" -gt 0 ]; then
      printf '  cooldown %ds...\n' "$cooldown"
      sleep "$cooldown"
    fi
  fi

  return 0
}

# ============================================================
# Per-repo worker (= 同 repo 内 Phase を直列に処理)
# ============================================================
run_repo_worker() {
  local repo="$1"
  local repo_log="$LOG_DIR/worker-${repo}.log"
  printf 'worker[%s] starting (log: %s)\n' "$repo" "$repo_log"

  local processed=0
  local pending_list
  pending_list=$(list_pending_phases | awk -v r="$repo" -F'\t' '$1 == r')

  if [ -z "$pending_list" ]; then
    printf 'worker[%s] no pending phases\n' "$repo"
    return 0
  fi

  while IFS=$'\t' read -r r c p f; do
    [ -z "$r" ] && continue
    # paused / stop check
    if [ "$(state_get '.paused')" = "true" ]; then
      printf 'worker[%s] paused → stopping\n' "$repo"
      return 0
    fi

    if ! run_phase "$r" "$c" "$p" "$f" >> "$repo_log" 2>&1; then
      printf 'worker[%s] fatal stop\n' "$repo"
      return 2
    fi
    processed=$((processed + 1))

    # max-phases per session
    if [ "$MAX_PHASES" -gt 0 ] && [ "$processed" -ge "$MAX_PHASES" ]; then
      printf 'worker[%s] reached max_phases=%d → ending session\n' "$repo" "$MAX_PHASES"
      return 0
    fi
  done <<< "$pending_list"

  printf 'worker[%s] done (processed=%d)\n' "$repo" "$processed"
  return 0
}

# ============================================================
# Scheduler main
# ============================================================
REPOS=()
if [ -n "$ONLY_REPO" ]; then
  REPOS=("$ONLY_REPO")
else
  while IFS= read -r r; do REPOS+=("$r"); done < <(jq -r '.repos | keys[]' "$STATE_FILE")
fi

printf 'repos to process: %s\n' "${REPOS[*]}"
printf '\n'

if [ "$SERIAL" = "true" ] || [ "${#REPOS[@]}" -eq 1 ]; then
  # 直列実行
  for repo in "${REPOS[@]}"; do
    if ! run_repo_worker "$repo"; then
      printf 'aborting due to fatal stop in %s\n' "$repo" >&2
      exit 2
    fi
  done
else
  # 並列実行
  declare -a worker_pids
  for repo in "${REPOS[@]}"; do
    run_repo_worker "$repo" &
    worker_pids+=($!)
  done
  printf 'spawned %d parallel workers: %s\n' "${#worker_pids[@]}" "${worker_pids[*]}"

  # 全 worker 終了待ち
  any_failed=0
  for pid in "${worker_pids[@]}"; do
    if ! wait "$pid"; then
      any_failed=1
    fi
  done
  if [ "$any_failed" -eq 1 ]; then
    printf 'one or more workers failed\n' >&2
    exit 2
  fi
fi

# ============================================================
# 完了 summary
# ============================================================
printf '\n=== Final Summary ===\n'
jq '{
  paused, stop_reason,
  totals: (.repos | to_entries | map({
    repo: .key,
    done: .value.phase_total_done,
    total: .value.phase_total,
    all_pass: .value.summary.all_pass_count,
    scope_cut: .value.summary.scope_cut_count,
    error: .value.summary.error_count,
    critical: .value.summary.critical_count
  }))
}' "$STATE_FILE"

exit 0
