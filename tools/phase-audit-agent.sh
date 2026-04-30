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
# OUTPUT_PATH に repo 名 / course を含めるための prefix (= 並列 worker で同じ PHASE_ID を持つ repo の衝突防止)
OUTPUT_DIR="${OUTPUT_DIR:-/tmp}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-phase-${PHASE_ID}}"

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

# portable timeout (Mac は GNU timeout 不在 / gtimeout が brew にあれば優先)
TIMEOUT_CMD=""
if command -v gtimeout >/dev/null; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null; then
  TIMEOUT_CMD="timeout"
fi

# bash 内蔵 fallback timeout (TIMEOUT_CMD が空のときのみ使う)
run_with_timeout() {
  local secs="$1"; shift
  if [ -n "$TIMEOUT_CMD" ]; then
    "$TIMEOUT_CMD" "$secs" "$@"
    return $?
  fi
  # fallback: bash background + watchdog kill
  "$@" &
  local child_pid=$!
  (
    sleep "$secs"
    kill -TERM "$child_pid" 2>/dev/null
    sleep 5
    kill -KILL "$child_pid" 2>/dev/null
  ) &
  local watchdog_pid=$!
  wait "$child_pid" 2>/dev/null
  local child_exit=$?
  kill "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  return $child_exit
}

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

  ROUND_OUTPUT="${OUTPUT_DIR}/${OUTPUT_PREFIX}-r${round}.md"
  ROUND_LOG="${OUTPUT_DIR}/${OUTPUT_PREFIX}-r${round}.log"

  PROMPT=$(cat <<EOF
${RUNBOOK_FILE} を読み、commit ${TARGET_SHA} の snapshot として Phase ${PHASE_ID} (file: ${PHASE_FILE}) の R${round} 監査を実施。**5 軸レビュー (正確性 / 可読性 / アーキテクチャ / セキュリティ / パフォーマンス)** を Next.js + Supabase 文脈で ULTRATHINK 適用すること。各軸で必ず 1 件以上は確認し、該当なしなら明示すること。

【5 軸の観点】

1. **[正確性] (Correctness)**: モデル名・SDK バージョン・URL・公式仕様・価格・引用が **2026 時点で現役**か。具体的な deprecated 例:
   - OpenAI: GPT-4 / GPT-4-Turbo / GPT-4o / GPT-4o-mini / GPT-3.5 / text-davinci-003 / Codex (古い) → GPT-5.5 / GPT-5 / GPT-5-mini が現役
   - Anthropic: Claude 2 / Claude 3 / Sonnet 3.5 / Sonnet 3.7 / Sonnet 4.5 / Opus (無印) / Haiku 3 → Opus 4.7 / Sonnet 4.6 / Haiku 4.5 が現役
   - Next.js: 13 / 14 / 15 / Pages Router → Next.js 16 + App Router が現役
   - Node.js: 18 (deprecated) / 20 → 22 / 24 LTS が現役
   - Supabase: 旧 anon/service_role key → sb_publishable_/sb_secret_ プレフィックスが現役
   - Vercel: Vercel Postgres / Vercel KV (廃止) / Edge Functions (非推奨) / vercel.json (推奨は vercel.ts) / 旧 default timeout 60s → 300s
   - その他: 旧 API endpoint / 旧 docs URL / 古い price / npm package の deprecated 警告 / 公式 docs と乖離した記述
   - 教材コンテンツ: 心理学・経営学・学術用語や理論の現役性 (denounced 理論名 / 旧称 / 改名された概念) / 引用書籍の絶版・改訂版差分 / 統計データの年度陳腐化 / 参照 URL の生死 (link rot) / 業界用語の変遷 / 法令・規制の改正反映

2. **[可読性] (Readability)**: 受講者 (経営者) が学習効率良く読めるか。用語の整合 / 段階的誘導 / 矛盾 / 冗長性 / 図示の必要性 / 業務文脈との結びつき。

3. **[アーキテクチャ] (Architecture)**: 構造的妥当性。層境界 / 依存関係 / SoC / 抽象化レベル / 拡張性 / 命名 / 責務分離 / Phase 間の前提継承。

4. **[セキュリティ] (Security)**: Fix 6 横断 6 観点 (RLS / OAuth cookie / secret 管理 / prompt injection / PII redact / supply-chain) + op:// reference / atomic + Negative test / 漏洩時停止条件 / 既存境界保持 chain。

5. **[パフォーマンス] (Performance)**: コスト (API 課金 / トークン量 / モデル使い分け) / レート (rate limit / per-user / per-workspace) / Core Web Vitals (LCP/INP/CLS) / N+1 / cache / bundle size / cold start / メモリ / バッチ化 / streaming.

【出力規則】
- 各 finding は **冒頭に軸タグ [正確性] [可読性] [アーキテクチャ] [セキュリティ] [パフォーマンス]** を付与し、severity (Critical / High / Medium / Low) と file:line を併記
  形式例: [High] [正確性] [app/foo/phase40401.ts:31] GPT-4o は 2026-04 時点で deprecated
- Critical/High が無い場合は明示すること
- **最終行は必ず: [総合判定: Critical×N + High×N + Medium×N + Low×N]** (既存の集計 grep 互換のため厳守)
EOF
)

  if ! run_with_timeout "$TIMEOUT_SEC" codex exec -s read-only -m "$MODEL" -c "model_reasoning_effort=$REASONING" \
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
printf 'Output dir: %s/%s-r*.md\n' "$OUTPUT_DIR" "$OUTPUT_PREFIX"
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
