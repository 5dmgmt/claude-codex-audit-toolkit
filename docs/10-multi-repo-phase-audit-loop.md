# 10. Multi-repo Phase 監査エージェントループ設計 (4 repo / 325 Phase 全自走 / コンパクト跨ぎ resume)

## 位置づけ

[`docs/09`](09-phase-audit-agent-loop-design.md) の単一 repo / 15 Phase prototype を、**4 repo (Workshop / RUN / SIFT / CPN) × 全 Course × 325 監査単位** の本番運用 SaaS への適用に拡張する設計文書。コンパクト跨ぎ resume + 本番運用ガード + Critical 検出時の人間判断介入を組み込む。

> 本ドキュメントは **claude-codex-audit-toolkit dogfooding 第 2 段** として、aifcc-workshop / aifcc-run / aifcc-sift / aifcc-cpn の Phase 単位品質監査を完全自動化するための設計。Phase 監査は教材 / コードベース 双方の品質保証を兼ねる。

## 規模感

| 項目 | 値 | 備考 |
|---|---|---|
| Workshop Phase 数 | **165** | course0-5 (course0=3, c1=15, c2=31, c3=56, c4=36, c5=24) |
| RUN Phase 数 | **46** | Course 1-5 (c1=6, c2=11, c3=10, c4=9, c5=10) |
| SIFT Phase 数 | **99** | course1-7 (c1-6=15 each, c7=9) |
| CPN 監査単位 | **15** | lib/courses/course*-*.ts (1 ファイル = 1 監査単位 / phase split は v0.7+) |
| **合計 監査単位** | **325** | inventory script で実数取得 (audit-phase-inventory.sh) |
| 1 単位完走時間 | 18-45 分 | 監査 (4-10 分) × 3 round + 反映 (2-5 分/round) |
| **総時間予算** | **約 50 時間 (4 並列)** | 数日にわたる長期ループ (= 数セッション分割 + compact 跨ぎ resume) |
| **API コスト粗算** | **$700-1400** | Codex 利用料 (監査単位 × round × token) |
| commit 上限 | ≈ 1000 | 修正 1 件 = 1 commit / 単位平均 3 commits |

**1 セッションでは完走不可** → コンパクト跨ぎ resume 設計が必須。

## 全体アーキテクチャ

```
[Claude Code 親プロセス (セッション開始)]
   └─ tools/multi-repo-audit-agent.sh --resume
        │
        ├─ state.json (~/audit-multi-repo-state.json) を Read
        ├─ paused == true → exit + 「unpause で再開」案内
        ├─ stop_reason != null → exit + 「stop_reason 解消後に再開」案内
        │
        ├─ Phase scheduler ループ:
        │   ├─ 並列 worker (4 個 / 1 個ずつ各 repo を担当)
        │   │   ├─ worker 1: aifcc-workshop の current Phase
        │   │   ├─ worker 2: aifcc-run の current Phase
        │   │   ├─ worker 3: aifcc-sift の current Phase
        │   │   └─ worker 4: aifcc-cpn の current Phase
        │   │
        │   ├─ 各 worker の per-Phase ループ:
        │   │   ├─ codex exec で監査 (gpt-5.5 xhigh / timeout 10 分 / retry 3)
        │   │   ├─ 結果パース (Critical/High/Medium/Low + 件数 + 凍結再指摘 detect)
        │   │   ├─ 終了条件 (ALL PASS / scope_cut / Critical / round 上限)
        │   │   ├─ 自動反映 (Claude Code subagent / Agent tool)
        │   │   │   ├─ Read finding → Edit → type-check + lint + build → commit + push
        │   │   │   ├─ build 失敗 → git restore + 「skip 判定」を返す
        │   │   │   └─ smoke test (curl /api/health) → 失敗で revert + 該当 repo 停止
        │   │   ├─ AUDIT_RUNBOOK.md 末尾に R{N} 反映済追記
        │   │   ├─ state.json 更新 (round / status / commits)
        │   │   └─ 5 分 cooldown (Vercel deployment 安定化待ち)
        │   │
        │   └─ 致命停止条件 check (各 worker 完了後):
        │       ├─ Critical 検出 → 全 repo 即停止 + paused: true (人間判断必須)
        │       ├─ 連続 3 abort (per repo) → 該当 repo 停止
        │       ├─ build 失敗 連続 5 → 全 repo 停止 (= リファクタ必要)
        │       └─ 凍結項目再指摘 連続 3 → 該当 repo 停止
        │
        └─ scheduler ループ (paused == true or all phases done まで)
            └─ 全 phase done → audit-summary.md 生成 + Discord 通知 (任意)
```

## state.json schema

絶対パス `~/audit-multi-repo-state.json` で管理 (= compact / clear で消えない / 別セッションから読める)。

```json
{
  "version": "1.0",
  "started_at": "2026-04-29T00:00:00+09:00",
  "last_updated_at": "...",
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
      "aifcc-sift": "https://sift.aifcc.jp/",
      "aifcc-cpn": "https://cpn.aifcc.jp/"
    }
  },
  "repos": {
    "aifcc-workshop": {
      "path": "/Users/5dmgmt/Plugins/aifcc-workshop",
      "current_focus": {
        "course": "course1",
        "phase": "10101",
        "round": 1
      },
      "phase_total": 75,
      "phase_total_done": 0,
      "courses": {
        "course1": {
          "phase_total": 15,
          "phases": {
            "10101": {
              "file": "app/workshop/data/phases/course1/phase10101.ts",
              "status": "pending",
              "rounds": [],
              "started_at": null,
              "ended_at": null,
              "review_notes": null
            }
          }
        }
      },
      "summary": {
        "all_pass_count": 0,
        "scope_cut_count": 0,
        "aborted_count": 0,
        "error_count": 0,
        "critical_count": 0,
        "total_commits": 0,
        "total_duration_sec": 0
      }
    },
    "aifcc-run": {/*...*/},
    "aifcc-cpn": {/*...*/}
  },
  "global_summary": {
    "consecutive_abort": 0,
    "consecutive_build_failure": 0,
    "consecutive_frozen_recidive": 0
  },
  "paused": false,
  "stop_reason": null
}
```

## 並列化戦略

| 並列度 | 軸 | 理由 |
|---|---|---|
| 4 並列 | repo 軸 (Workshop / RUN / SIFT / CPN 同時) | Codex API レート制限 + Vercel deployment 安定化を考慮した最大並列 |
| 直列 | 同 repo 内 Phase 軸 | 共通インフラ層問題 (e.g., R1 cookie 属性) を発見しやすくする / commit pin 純度維持 |
| 直列 | 同 Phase 内 round 軸 | 五月雨防止 v2 の precondition 蓄積 / 修正反映後に次 round |

## コンパクト跨ぎ resume

セッションが落ちる / `/clear` / `/compact` で親プロセスが死んでも、`state.json` の `status="running"` 以降から再開可能。

### resume 手順

```bash
# 新セッション開始時 (Claude Code)
"audit を resume してください"

# Claude Code が実行する内容
cat ~/audit-multi-repo-state.json | jq '.current_focus'  # 現在の進捗確認
./tools/multi-repo-audit-agent.sh --resume
```

### resume ロジック

1. state.json 読み込み
2. `paused == true` → exit + unpause コマンド案内
3. `stop_reason != null` → exit + 解消後に再開する手順案内
4. 各 repo の `current_focus.phase` が `status="running"` なら現 round から retry (= Codex 監査再起動)
5. `status="completed/all_pass/scope_cut"` の Phase はスキップ
6. `status="pending"` の Phase を順次

### chunked execution

1 セッション (Claude Code) で 100% 完走を期待しない:
- 1 セッションで 5-20 Phase 完走 → compact → 次セッションで resume
- 各セッションで 30-60 分の進捗

## 本番運用ガード

aifcc-workshop / aifcc-run / aifcc-sift / aifcc-cpn は本番運用 SaaS で受講者リアルタイム影響あり。以下のガードを必須:

| ガード | 内容 | 失敗時 |
|---|---|---|
| 5 分 cooldown | High 以上修正後の Vercel deployment 安定化待ち | 待機のみ |
| smoke test | 修正後 `curl https://{domain}/api/health` で 200 確認 | revert + 該当 repo 停止 |
| Critical 自動停止 | Critical 検出時は **自動修正禁止** | 全 repo 停止 + 人間判断 |
| build 失敗連続 5 | リファクタ必要のサイン | 全 repo 停止 |
| AI 文字エンコーディング検証 | NBSP / zero-width / 絵文字混入 detect | 該当修正を skip |

## 致命停止条件

| 条件 | アクション | 復旧 |
|---|---|---|
| Critical 検出 | 全 repo 即停止 + `stop_reason: "critical_detected"` | 人間が判断 + Critical 修正後に `paused: false` で再開 |
| 連続 3 abort (per repo) | 該当 repo 停止 / 他 repo は継続 | 失敗 round の log 解析後に `repos.<name>.paused: false` |
| build 失敗 連続 5 | 全 repo 停止 + `stop_reason: "build_instability"` | リファクタ後に再開 |
| 凍結項目再指摘 連続 3 | 該当 repo 停止 | precondition 強化後に再開 |
| ユーザー Ctrl+C | trap で `paused: true` | round 境界で安全停止 / 後で `--resume` |

## Claude Code subagent ハンドオフ

各 round で P1/Critical/High finding を反映する subagent を `Agent tool` (general-purpose) で起動:

```
prompt:
あなたは {repo_name} の Phase {phase_id} R{round} 監査結果から finding を反映する subagent。

# 入力
- finding: {Critical/High/Medium 詳細 + 修正案}
- 関連ファイル: {file paths}
- 制約: {repo} の CLAUDE.md ルール (TypeScript / 絵文字禁止 / 7 色パレット / RLS 必須 / コミット前必須)

# やること (各 finding を 1 commit で / Critical は自動修正禁止 → skip 判定)
1. Critical があれば skip 判定 (人間判断要) → 全停止信号を返す
2. High / Medium を 1 件ずつ:
   a. 該当ファイルを Read
   b. 修正案を Edit で反映
   c. `npm run type-check && npm run lint && npm run build` を実行
   d. 失敗したら `git restore <file>` で revert + 「skip 判定」
   e. 成功したら `git add <file> && git commit -m "fix(phase{id}): R{round} {Severity} - {概要}"`
   f. `git push origin main` (= main 直 push、CLAUDE.md ルール)
   g. smoke test: `curl -s -o /dev/null -w '%{http_code}' {smoke_test_url}` が 200 か確認
   h. smoke test 失敗 → 該当 commit を revert (`git revert HEAD`) + push + 「skip 判定」
   i. 5 分 cooldown
3. 反映 commit SHA + 状態を返す

# 制約
- main 直 push (CLAUDE.md ルール)
- Critical は自動修正禁止
- `.archive/` import 禁止 / `any` 乱用禁止
```

## 実装段階

| Step | 内容 | 期間 | コンパクト前/後 |
|---|---|---|---|
| 1 | 設計文書 docs/10 (本ドキュメント) + state.json schema 確定 | 30 分 | 前 |
| 2 | tools/audit-state-init.sh (state 初期化スクリプト) | 15 分 | 前 |
| 3 | tools/RESUME-AUDIT-LOOP.md (コンパクト後の手順書) | 15 分 | 前 |
| 4 | tools/multi-repo-audit-agent.sh skeleton + scheduler | 60 分 | 後 |
| 5 | per-Phase ループ実装 (codex exec / 結果パース / 終了条件) | 60 分 | 後 |
| 6 | Claude Code subagent ハンドオフ実装 | 60 分 | 後 |
| 7 | 本番運用ガード (smoke test / cooldown / Critical 停止) | 30 分 | 後 |
| 8 | 単体テスト (1 repo / 1 Phase 実走) | 30 分 | 後 |
| 9 | 4 repo / 5 Phase で dry-run | 60 分 | 後 |
| 10 | 全 Phase 本番実走 (= 数日 + コンパクト跨ぎ resume) | 数日 | 後 |

## 段階的拡張

| 段階 | scope | リスク |
|---|---|---|
| Phase A (本ドキュメント) | 設計確定 + 初期化 + resume 手順 | 低 |
| Phase B | 単一 repo / 単一 Course / 5 Phase 自走 (dry-run) | 中 |
| Phase C | 単一 repo / 全 Course 自走 | 中 |
| Phase D | 4 repo 並列自走 (本番) | 高 |
| Phase E | Quiz / 用語 / Workshop の Phase 監査ランブック自走 | 高 |

## 残課題 (v0.6 / v1.0 で再判定)

- **Codex API 並列レート制限の実証**: 4 並列で問題ないか実際に走らせて確認
- **deployment 安定化の数値化**: 5 分 cooldown は仮 / Vercel deployment が確定する時間を計測
- **smoke test の網羅性**: `/api/health` が無い場合は `/` (LP) の curl で代替
- **AUDIT_RUNBOOK.md の蓄積爆発**: Phase ごとに `PHASE_RUNBOOK_{id}.md` 分割を検討
- **Critical 検出時の通知**: Discord webhook で人間に即通知 (任意)

## 関連文書

- [`09-phase-audit-agent-loop-design.md`](09-phase-audit-agent-loop-design.md) — 単一 repo prototype (本拡張の親モデル)
- [`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) — 五月雨防止 v2 (precondition 蓄積)
- [`03-five-decisive-fixes.md`](03-five-decisive-fixes.md) — Fix 1 (commit pin) / Fix 6 (横断 6 観点)
- [`04-convergence-patterns.md`](04-convergence-patterns.md) — 収束判定 4 条件
- [`tools/phase-audit-agent.sh`](../tools/phase-audit-agent.sh) — docs/09 prototype v0.1
- [`examples/aifcc-workshop-snippet.md`](../examples/aifcc-workshop-snippet.md) — Workshop dogfooding R1
