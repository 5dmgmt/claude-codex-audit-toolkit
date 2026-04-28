#!/usr/bin/env bash
# tools/audit-smoke-test.sh — Vercel deployment 後の smoke test
#
# 修正反映 + push 後の Vercel deployment 安定化待ち + 200 確認。
# 失敗時は呼び出し側 (subagent or scheduler) が revert + 該当 repo 停止する。
#
# Usage:
#   ./tools/audit-smoke-test.sh <URL> [<COOLDOWN_SEC>] [<RETRIES>]
#
# 例:
#   ./tools/audit-smoke-test.sh https://workshop.aifcc.jp/ 300 3
#
# 引数:
#   URL          smoke test URL (必須 / 末尾 / は付けても付けなくても良い)
#   COOLDOWN_SEC deployment 安定化待ち秒 (デフォルト: 300 = 5 分)
#   RETRIES      200 受信 retry 回数 (デフォルト: 3 / 30 秒間隔)
#
# 終了 status code:
#   0 — 200 OK
#   1 — 引数不足 / curl 不在
#   2 — non-200 (revert 候補 / status code を stdout 末尾に出力)
#   3 — タイムアウト / 接続不能 (Vercel ダウンの可能性 / pause 候補)

set -euo pipefail

URL="${1:?Usage: audit-smoke-test.sh <URL> [<COOLDOWN_SEC>] [<RETRIES>]}"
COOLDOWN_SEC="${2:-300}"
RETRIES="${3:-3}"
SLEEP_BETWEEN_RETRIES=30
CURL_TIMEOUT=15

command -v curl >/dev/null || { printf 'FAIL: curl not found\n' >&2; exit 1; }

printf '=== smoke test ===\n'
printf 'URL:       %s\n' "$URL"
printf 'cooldown:  %ds (Vercel deployment 安定化待ち)\n' "$COOLDOWN_SEC"
printf 'retries:   %d (30s 間隔)\n' "$RETRIES"
printf '\n'

if [ "$COOLDOWN_SEC" -gt 0 ]; then
  printf 'cooldown sleep %ds...\n' "$COOLDOWN_SEC"
  sleep "$COOLDOWN_SEC"
fi

attempt=1
last_code=""
while [ "$attempt" -le "$RETRIES" ]; do
  printf 'attempt %d/%d: GET %s\n' "$attempt" "$RETRIES" "$URL"

  set +e
  HTTP_CODE=$(curl -s -L -o /dev/null --max-time "$CURL_TIMEOUT" -w '%{http_code}' "$URL")
  CURL_EXIT=$?
  set -e

  if [ "$CURL_EXIT" -ne 0 ]; then
    printf '  curl error (exit=%d / 接続不能)\n' "$CURL_EXIT"
    last_code="curl_exit_${CURL_EXIT}"
  else
    printf '  HTTP %s\n' "$HTTP_CODE"
    last_code="$HTTP_CODE"
    if [ "$HTTP_CODE" = "200" ]; then
      printf '\nOK: smoke test passed (%s)\n' "$URL"
      exit 0
    fi
  fi

  if [ "$attempt" -lt "$RETRIES" ]; then
    printf '  retry sleep %ds...\n' "$SLEEP_BETWEEN_RETRIES"
    sleep "$SLEEP_BETWEEN_RETRIES"
  fi
  attempt=$((attempt + 1))
done

printf '\n'
printf 'FAIL: smoke test did not return 200 after %d attempts\n' "$RETRIES"
printf 'last_code: %s\n' "$last_code"

# 終了コード分岐
case "$last_code" in
  curl_exit_*)  exit 3 ;;  # 接続不能
  *)            exit 2 ;;  # non-200 (revert 候補)
esac
