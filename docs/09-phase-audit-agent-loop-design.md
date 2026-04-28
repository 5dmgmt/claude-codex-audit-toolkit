# 09. Phase 監査エージェントループ設計 (15 Phase × N ラウンド自走 / 止まらない設計)

## 位置づけ

`AIFCC Workshop Course 1` の **15 Phase を 1 Phase = N ラウンドの自走監査ループ** で回す Claude Code subagent + bash スクリプト hybrid の設計文書。本リポの単発「コードベース監査 / ランブック監査」とは別軸の **Phase 単位の教材品質監査** を、人間が逐一介入せず連続実行できる仕組みにする。

v1.0 到達条件 (2) 「AIFCC Workshop での本格教材化 + cohort 検証 1 周」の前段として、本ループで Course 1 完走 → 学習点を本リポに fold back する。

## 全体アーキテクチャ

```
[Claude Code 親プロセス (人間がセッション開始)]
   └─ phase-audit-agent.sh (bash 外側ループ / 1 セッションで完走想定)
        │
        ├─ for phase_id in $PHASE_IDS (15 Phase 直列):
        │   │
        │   └─ while round < 5 && status ∉ {all_pass, scope_cut, aborted}:
        │       │
        │       ├─ [a] codex exec gpt-5.5 xhigh + timeout 10 分 + retry 3
        │       │     └─ 結果 /tmp/round-{phase}-{round}.md
        │       │
        │       ├─ [b] 結果パース ([総合判定: P1×N + P2×N + P3×N] or [ALL PASS])
        │       │     ├─ ALL PASS → status = all_pass / break while
        │       │     ├─ round == 5 → status = scope_cut / break
        │       │     ├─ 同一件数停滞 2 連続 → status = scope_cut / break
        │       │     ├─ 凍結項目再指摘 (2 回目) → status = scope_cut / break
        │       │     └─ それ以外 → P1 finding 抽出
        │       │
        │       ├─ [c] Claude Code subagent (Agent tool / general-purpose)
        │       │     prompt: 「P1 finding 反映 / type-check + lint + build / 失敗 revert / 1 違和感 = 1 commit + push」
        │       │     終了後 audit-state.json 更新 (commits / status)
        │       │
        │       ├─ [d] AUDIT_RUNBOOK.md (or PHASE_RUNBOOK_{id}.md) 末尾に R{N} 反映済追記
        │       │
        │       └─ round++ → loop
        │
        └─ all phases done → audit-summary.md 生成 + 完了通知
```

## per-Phase ループ (内側)

### 1 ラウンドの流れ

| step | 内容 | 失敗時 |
|---|---|---|
| (a) Codex 監査起動 | `codex exec -s read-only -m gpt-5.5 -c model_reasoning_effort=xhigh --output-last-message /tmp/round-{phase}-{round}.md "${PROMPT}" < /dev/null` / timeout 10 分 | retry 3 回 (1/2/4 分 backoff) → 全失敗で scope cut |
| (b) 結果集計 | `grep '総合判定' /tmp/round-...md \| tail -1` / regex パース | 判定行不在 → 「Codex 出力異常」として scope cut |
| (c) 終了条件チェック | 後述の判定マトリクス | 該当条件で break |
| (d) P1 finding 反映 | Claude Code subagent (Agent tool) にハンドオフ | type-check / lint / build 失敗 → 自動 git restore + finding skip |
| (e) 蓄積リスト更新 | AUDIT_RUNBOOK.md / PHASE_RUNBOOK_{id}.md 末尾追記 | jq / sed エラー → log + 次 round |
| (f) round++ | state.json の rounds 配列に append | - |

### 終了条件マトリクス

| 条件 | アクション | 根拠 |
|---|---|---|
| `総合判定 == ALL PASS` | status = `all_pass` / break | 真の収束 |
| `round == 5` | status = `scope_cut` + `_review-notes-phase{id}.md` 転記 | Workshop 4R + 余裕 1R |
| 同一範囲件数停滞 2 連続 (P1+P2+P3 が前ラウンド比 0% 減) | status = `scope_cut` | docs/04 scope creep 条件 |
| 凍結項目への再指摘 (precondition 違反 2 回目) | status = `scope_cut` | 五月雨指摘 cascade |
| 矛盾指摘 (前ラウンド方針否定 / 注記なし) | 1 round だけ rerun → 改善なければ scope cut | 五月雨防止プロンプト v2 |
| Codex プロセス hang (timeout) 連続 2 回 | status = `aborted` (model 切替提案) | video-subtitler の hang 経験 |

## 全 Phase 外側ループ

```bash
PHASE_IDS=(10101 10102 10103 10201 10202 10203 10301 10302 10303 10401 10402 10403 10501 10502 10503)
consecutive_failures=0

for phase_id in "${PHASE_IDS[@]}"; do
  if audit-phase "$phase_id"; then
    consecutive_failures=0
  else
    consecutive_failures=$((consecutive_failures + 1))
    [ "$consecutive_failures" -ge 3 ] && { log "abort: 連続 3 Phase 失敗"; break; }
  fi
done
```

## 状態管理 (audit-state.json)

```json
{
  "course_id": 1,
  "started_at": "2026-04-28T22:30:00+09:00",
  "ended_at": null,
  "config": {
    "max_rounds_per_phase": 5,
    "per_round_timeout_sec": 600,
    "global_consecutive_failure_limit": 3,
    "model": "gpt-5.5",
    "reasoning_effort": "xhigh",
    "fallback_model": "gpt-5.4"
  },
  "phases": {
    "10101": {
      "status": "all_pass",
      "rounds": [
        {"round": 1, "p1": 5, "p2": 12, "p3": 3, "fixed_commits": ["abc123","def456"], "duration_sec": 320},
        {"round": 2, "p1": 0, "p2": 4, "p3": 1, "fixed_commits": [], "duration_sec": 280}
      ],
      "started_at": "...", "ended_at": "..."
    },
    "10102": {
      "status": "scope_cut",
      "rounds": [/*...*/],
      "review_notes": "docs/_review-notes-phase10102.md",
      "started_at": "...", "ended_at": "..."
    },
    "10103": {"status": "running", "current_round": 3, "started_at": "..."},
    "10201": {"status": "pending"}
  },
  "summary": {
    "all_pass_count": 1,
    "scope_cut_count": 1,
    "aborted_count": 0,
    "error_count": 0,
    "total_commits": 12,
    "total_duration_sec": 9200
  },
  "paused": false
}
```

### resume 性

セッションが落ちる / `/clear` / `/compact` で親プロセスが死んでも、`audit-state.json` の `status="running"` 以降から再開可能。`status="pending"` は未着手なのでそのまま続行、`status="running"` は中断扱いで現 round から retry。

## 止まらない仕組み (障害カテゴリ別対処)

| カテゴリ | 障害 | 対処 |
|---|---|---|
| **環境** | Codex 認証切れ / network error | retry 3 回 (1/2/4 分 exponential backoff) → ダメなら status = `error` / 次 Phase |
| **環境** | model 不在 (gpt-5.5 表示されない) | `fallback_model` (gpt-5.4) に切替 (codex exec の stderr 解析) |
| **環境** | timeout (10 分) | プロセス kill → retry 1 回 → ダメなら scope cut |
| **品質** | 矛盾指摘 (前ラウンド否定 / 注記なし) | precondition 強化 + 1 round 警告 → 改善なければ scope cut |
| **品質** | 凍結項目再指摘 | 1 回目 = 警告 + 凍結追加 / 2 回目 = scope cut |
| **品質** | 上限 5 round 到達 | scope cut + 残 finding を `_review-notes-phase{id}.md` に転記 |
| **反映** | type-check / lint / build 失敗 | 未 commit なら `git restore` で revert / commit 後なら `git reset --hard HEAD~1` (push 前限定) → finding skip + 次 round |
| **反映** | 反映不可 (abstract / 既存 design 範囲外) | subagent が「skip 判定」を出す → finding を `_review-notes` に転記 |
| **state** | 親プロセス clear / compact | audit-state.json から status=`running` の Phase を再開 |
| **state** | 全体 budget 超過 (12.5 時間目安) | 現在 Phase 完了後に `paused: true` をセット + summary 生成 |
| **safety** | ユーザー停止 (Ctrl+C) | trap で `paused: true` セット → 次 round 境界で安全停止 |

## safety (暴走防止)

| 制約 | 値 | 根拠 |
|---|---|---|
| per-Phase round 上限 | 5 ラウンド | Workshop 4R + 余裕 1R (SIFT 13R は exception ケース) |
| per-round timeout | 10 分 | gpt-5.5 ランブック監査の典型 4-10 分 |
| per-Phase 最大時間 | 50 分 | round 上限 × timeout |
| 全体 budget | 15 Phase × 50 分 = 12.5 時間 | 1 セッション内で完走想定 |
| auto commit 上限 | 75 commit | 1 Phase 5 commit × 15 (= 暴走時の上限) |
| 連続 abort 上限 | 3 Phase | 全体停止条件 |
| ユーザー停止 | `audit-state.json` の `paused: true` セット (Ctrl+C trap) | 安全停止 (round 境界) |

## ハンドオフ (subagent prompt)

P1 finding 反映時の Claude Code subagent (Agent tool / general-purpose) prompt 例:

```
あなたは Phase {phase_id} (file: {phase_file}) の R{round} 監査結果から P1 finding を反映する subagent。

# 入力
- finding: {P1 finding 詳細 + 修正案}
- 関連ファイル: {phase_file}
- 制約: aifcc-workshop CLAUDE.md ルール (TypeScript / 絵文字禁止 / 7 色パレット / RLS 必須 / コミット前必須コマンド)

# やること
1. 該当ファイルを Read
2. finding の修正案を Edit で反映
3. `npm run type-check && npm run lint && npm run build` を実行
4. 失敗したら `git restore <file>` で revert + 「skip 判定」を返す (理由: build 失敗)
5. 成功したら `git add <file> && git commit -m "fix(phase{id}): R{round} P1 - {finding 概要}"` で 1 commit
6. `git push origin main`
7. 反映 commit SHA + 状態を返す

# 制約
- 1 違和感 = 1 commit (atomic)
- main 直 push (CLAUDE.md ルール)
- `.archive/` import 禁止 / `any` 乱用禁止
- 範囲外なら無理に直さず skip
```

## 実装段階

| Step | 内容 | 期間目安 |
|---|---|---|
| 1 | 設計確定 (本ドキュメント) | 1 セッション |
| 2 | prototype 実装 (1 Phase 手動完走 / `tools/phase-audit-agent.sh` v0.1) | 1 セッション |
| 3 | 1 Phase 自走テスト (10101 だけ自動で 1-3 round 完走) | 1 セッション |
| 4 | Course 1 全 15 Phase 直列実走 + summary 生成 | 1 セッション (12 時間予算) |
| 5 | 結果を本リポに fold back (例: 「Phase 監査での Fix 7 = N=1 から N=15 に拡張」等) | 1 セッション |

## 残課題 (未決定 / v1.0 で再判定)

- **並列化**: 15 Phase 並列で 50 分完走できるが Codex API レート制限の懸念 → 当面直列。R5 self-audit (19 並列) で実証済の並列度を再評価する余地あり
- **AUDIT_RUNBOOK.md の蓄積爆発**: 15 Phase × 5 round の蓄積で膨張 → Phase ごとに `PHASE_RUNBOOK_{id}.md` 分割を検討
- **model 動的選択**: 当面は `gpt-5.5 xhigh` 固定 (Phase は静的 .ts なのでランブック寄り)。コードベース要素が強い Phase は gpt-5.4 に切替も検討
- **human review point**: Phase scope cut 後の `_review-notes-phase{id}.md` レビューはセッション間で実施 (本ループは「自動反映 or scope cut」で止めず、ユーザーは事後レビュー)
- **凍結項目検出ロジック**: 「凍結項目再指摘」を機械的に判定するために `_review-notes-v0.4-beta-frozen.md` の項目に ID を付けて grep 可能化する案

## 関連文書

- [`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) — 五月雨防止 v2 (precondition 蓄積)
- [`03-five-decisive-fixes.md`](03-five-decisive-fixes.md) — Fix 1 (commit pin) / Fix 6 (横断 6 観点)
- [`04-convergence-patterns.md`](04-convergence-patterns.md) — 収束判定 4 条件 + scope cut
- [`07-runbook-templates/code-audit-runbook.md`](07-runbook-templates/code-audit-runbook.md) — 1 commit 監査の親モデル
- [`examples/aifcc-workshop-snippet.md`](../examples/aifcc-workshop-snippet.md) — aifcc-workshop dogfooding R1 結果 (本ループの直前段)
