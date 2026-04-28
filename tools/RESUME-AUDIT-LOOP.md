# Multi-repo Phase 監査ループ Resume 手順

> claude-codex-audit-toolkit v0.5-nextjs-supabase / docs/10 設計の **コンパクト跨ぎ resume 手順**。新セッション開始時、Claude Code に「audit を resume」と言えば本ファイルを参照して再開する。

## 現在の状況確認

```bash
# state.json 読み込み (= ~/audit-multi-repo-state.json)
cat ~/audit-multi-repo-state.json | jq '{
  paused,
  stop_reason,
  last_updated_at,
  current_focus_workshop: .repos["aifcc-workshop"].current_focus,
  current_focus_run: .repos["aifcc-run"].current_focus,
  current_focus_cpn: .repos["aifcc-cpn"].current_focus,
  totals: {
    workshop: { done: .repos["aifcc-workshop"].phase_total_done, total: .repos["aifcc-workshop"].phase_total },
    run: { done: .repos["aifcc-run"].phase_total_done, total: .repos["aifcc-run"].phase_total },
    cpn: { done: .repos["aifcc-cpn"].phase_total_done, total: .repos["aifcc-cpn"].phase_total }
  }
}'
```

## Resume 判定

| state | アクション |
|---|---|
| `paused: true` | 人間が原因確認 → `paused: false` にしてから resume |
| `stop_reason != null` | reason 解消 → `stop_reason: null` にしてから resume |
| `paused: false && stop_reason: null` | `tools/multi-repo-audit-agent.sh --resume` で再開 |

## 致命停止からの復旧

| stop_reason | 復旧手順 |
|---|---|
| `critical_detected` | 該当 finding (state.json `repos.<name>.summary.critical_count > 0` で参照) を Read → 人間判断で修正 (or 計画書化) → `stop_reason: null` |
| `build_instability` | 連続 build 失敗 5 回 = リファクタ必要 → 該当 commit / repo を Read → リファクタ commit → `stop_reason: null` |
| `consecutive_abort` | log 解析 (`/tmp/phase-*-r*.log`) → 環境系問題 (Codex 認証 / model 不在 / network) なら解消 → `stop_reason: null` |
| `consecutive_frozen_recidive` | precondition (各 repo の AUDIT_RUNBOOK.md 末尾) を強化 → `stop_reason: null` |

## 進捗を見る

```bash
# 完了した Phase 一覧
cat ~/audit-multi-repo-state.json | jq '
  .repos | to_entries[] | {
    repo: .key,
    completed: [
      .value.courses | to_entries[] |
      .value.phases | to_entries[] |
      select(.value.status == "all_pass" or .value.status == "scope_cut") |
      .key
    ]
  }
'

# 残 Phase 数
cat ~/audit-multi-repo-state.json | jq '
  .repos | to_entries[] | {
    repo: .key,
    remaining: (.value.phase_total - .value.phase_total_done)
  }
'
```

## 一時停止

ループ実行中に Ctrl+C:
- trap で `paused: true` セット
- 次の round 境界で安全停止
- log の最後の行に「次回 resume 時の Phase」を記録

または `~/audit-multi-repo-state.json` を手動編集して `paused: true` に。

## 完全リセット

```bash
# 全状態を消して新規開始 (注意: 進捗が消える)
rm ~/audit-multi-repo-state.json
./tools/audit-state-init.sh
```

## 各 repo の AUDIT_RUNBOOK.md 蓄積リスト確認

R2 以降は Codex prompt の precondition として AUDIT_RUNBOOK.md 末尾の §R{N} 反映済 セクションを使う。

```bash
for repo in aifcc-workshop aifcc-run aifcc-cpn; do
  printf '\n=== %s AUDIT_RUNBOOK.md ===\n' "$repo"
  tail -40 "/Users/5dmgmt/Plugins/${repo}/AUDIT_RUNBOOK.md"
done
```

## 関連文書

- [`../docs/10-multi-repo-phase-audit-loop.md`](../docs/10-multi-repo-phase-audit-loop.md) — 全体設計
- [`audit-state-init.sh`](audit-state-init.sh) — state.json 初期化
- [`phase-audit-agent.sh`](phase-audit-agent.sh) — 単一 repo prototype v0.1 (docs/09 Step 2)
- [`../docs/09-phase-audit-agent-loop-design.md`](../docs/09-phase-audit-agent-loop-design.md) — 単一 repo 設計

## コンパクト直前のチェックリスト

コンパクトする前に以下を確認:
- [ ] state.json (`~/audit-multi-repo-state.json`) が存在 (audit-state-init.sh 実行済)
- [ ] 3 repo 全部に AUDIT_RUNBOOK.md あり (Workshop ✅ / RUN ✅ / CPN ✅)
- [ ] 進行中の round が `status: "running"` のままなら次セッションで再開可能
- [ ] 未 commit / 未 push の修正があれば commit + push (= main 直押し)
- [ ] dirty file (next-env.d.ts 等 auto-regen) は無視 OK / Workshop チームの作業途中ファイルは触らない
- [ ] context 残量 30% 切ったら `/compact` でクリーンアップ

## コンパクト後の最初のメッセージ例

新セッションで Claude Code に:

```
audit-resume を確認して。~/audit-multi-repo-state.json と
claude-codex-audit-toolkit/tools/RESUME-AUDIT-LOOP.md を読んで、
現在の状況と次にやるべきことを 5 行以内で。
```

これで Claude Code が状態を読み込んで現状報告 → ユーザーが「continue」or 「stop」で判断。
