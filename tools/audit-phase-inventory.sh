#!/usr/bin/env bash
# tools/audit-phase-inventory.sh — 4 repo の Phase 構造を JSON で吐く
#
# Workshop / RUN / SIFT は app/{workshop|run|dashboard}/data/phases/course*/phase*.ts 個別
# CPN は lib/courses/course*-*.ts を 1 監査単位とする (v0.7+ で phase split 予定)
#
# Usage:
#   ./tools/audit-phase-inventory.sh > /tmp/inventory.json
#
# 出力 JSON 形式:
# {
#   "<repo>": {
#     "<course>": {
#       "<phase_id>": {"file": "<relative_path>", "status": "pending", "rounds": [], ...}
#     }
#   }
# }

set -euo pipefail

WORKSHOP=/Users/5dmgmt/Plugins/aifcc-workshop
RUN_REPO=/Users/5dmgmt/Plugins/aifcc-run
SIFT=/Users/5dmgmt/Plugins/aifcc-sift
CPN=/Users/5dmgmt/Plugins/aifcc-cpn

# 共通 phase entry 生成
phase_entry() {
  local file="$1"
  printf '{"file":"%s","status":"pending","rounds":[],"started_at":null,"ended_at":null,"review_notes":null}' "$file"
}

# repo + base_dir + name の course→phases 構造を JSON で出力
emit_phase_courses() {
  local repo_root="$1"
  local base_dir="$2"  # 例: app/workshop/data/phases
  cd "$repo_root"
  local sep_course=""
  printf '{'
  for course_dir in $(find "$base_dir" -maxdepth 1 -type d -name "course*" 2>/dev/null | sort); do
    local course_name
    course_name=$(basename "$course_dir")
    printf '%s"%s":{' "$sep_course" "$course_name"
    sep_course=","
    local sep_phase=""
    for phase_file in $(find "$course_dir" -maxdepth 1 -name "phase*.ts" -not -name "index.ts" | sort); do
      local rel_path
      rel_path="${phase_file#./}"
      local phase_id
      phase_id=$(basename "$phase_file" .ts | sed 's/^phase//')
      printf '%s"%s":' "$sep_phase" "$phase_id"
      phase_entry "$rel_path"
      sep_phase=","
    done
    printf '}'
  done
  printf '}'
}

# CPN は course file 自体を「phase」として扱う
emit_cpn_courses() {
  cd "$CPN"
  local base_dir="lib/courses"
  printf '{"all":{'
  local sep=""
  for course_file in $(find "$base_dir" -maxdepth 1 -name "course*.ts" -not -name "index.ts" -not -name "terms.ts" | sort); do
    local rel_path="$course_file"
    local course_id
    course_id=$(basename "$course_file" .ts)
    printf '%s"%s":' "$sep" "$course_id"
    phase_entry "$rel_path"
    sep=","
  done
  printf '}}'
}

# 出力
printf '{'
printf '"aifcc-workshop":'
emit_phase_courses "$WORKSHOP" "app/workshop/data/phases"
printf ','

printf '"aifcc-run":'
emit_phase_courses "$RUN_REPO" "app/run/data/phases"
printf ','

printf '"aifcc-sift":'
emit_phase_courses "$SIFT" "app/dashboard/data/phases"
printf ','

printf '"aifcc-cpn":'
emit_cpn_courses

printf '}'
