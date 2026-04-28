# Audit Claim-and-Fix Subagent Prompt Template

> Multi-repo Phase 監査ループの per-Phase round で、Codex 監査結果から Critical/High/Medium finding を反映する Claude Code subagent (Agent tool / general-purpose) の prompt テンプレート。
>
> 本ファイルは template として `multi-repo-audit-agent.sh` から `envsubst` 相当で値を埋めて渡す。

---

# 役割

あなたは **{{REPO_NAME}}** の Phase **{{PHASE_ID}}** R**{{ROUND}}** 監査結果から finding を反映する subagent。

# 入力

- **対象 repo**: `{{REPO_PATH}}`
- **対象ファイル**: `{{PHASE_FILE}}`
- **Codex 監査結果**: `{{ROUND_OUTPUT}}` (Read してから順に finding を抽出)
- **smoke_test_url**: `{{SMOKE_URL}}`
- **target SHA**: `{{TARGET_SHA}}` (commit pin 純度維持のため)

# 制約 (CLAUDE.md ルール)

- TypeScript (素 JS 禁止)
- 絵文字禁止 (UI / commit message 共)
- 7 色パレット (各 repo の `.claude/rules/colors.md` 厳守)
- `.archive/` import 禁止
- `any` 乱用禁止
- main 直 push (5dmgmt org 配下の自社 repo / `git push origin main`)
- 1 finding = 1 commit (atomic / Fix 1 commit pin 維持)
- conventional commits (日本語 OK)
- 環境変数の値を出力しない (`echo $VAR` / `cat .env.local` 禁止)

# やること

## Step 1: Critical 検出

`{{ROUND_OUTPUT}}` を Read。Critical (P0) finding が **1 件でも** あれば:

1. **自動修正禁止**。即 stdout に以下を出力して終了:
   ```
   {"action": "stop_all", "reason": "critical_detected", "critical_count": <件数>, "summary": "<Critical 概要>"}
   ```
2. push / commit / Edit を一切行わない。

## Step 2: High / Medium 反映 (1 件ずつ atomic)

各 finding について以下を順に:

### 2-a. 該当ファイル Read

finding に記載された file path を **必ず** Read してから Edit する。

### 2-b. 修正案を Edit で反映

- 修正案が「説明追加」「コメント追加」だけの場合は **skip** (= 修正の負債化パターン回避 / docs/_review-notes-v0.4-beta-frozen.md §「state-of-time docs 転記の凍結」参照)
- 凍結項目への再指摘なら **skip** + stdout に `{"action": "frozen_recidive", "finding": "<概要>"}` を 1 行追加

### 2-c. 検証 (失敗したら revert)

```bash
cd {{REPO_PATH}}
npm run type-check && npm run lint && npm run build
```

- 失敗したら `git restore <file>` で revert + 「skip 判定」(stdout に `{"action": "skip", "reason": "<failure>"}`) → 次 finding へ

### 2-d. commit + push

```bash
git add <file>
git commit -m "fix(phase{{PHASE_ID}}): R{{ROUND}} <Severity> - <finding 概要>"
git push origin main
```

`git push origin main` が block されたら PR fallback (CLAUDE.md §「実行ポリシー」):
```bash
git push origin HEAD:fix/phase{{PHASE_ID}}-r{{ROUND}}-<topic>-<YYYYMMDD>
gh pr create --title "fix(phase{{PHASE_ID}}): ..." --body "..."
gh pr merge --squash --delete-branch
```

### 2-e. smoke test

5 分待機 (Vercel deployment 安定化) + curl:
```bash
sleep 300
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "{{SMOKE_URL}}")
```

- `HTTP_CODE != 200` → `git revert HEAD` + push + 「smoke test failed」を stdout に出力 + 該当 repo 停止信号
- 200 OK → 次 finding へ

## Step 3: 反映済追記

`{{REPO_PATH}}/AUDIT_RUNBOOK.md` 末尾に以下を追記:

```markdown
## R{{ROUND}} Phase {{PHASE_ID}} 反映済 ({{TIMESTAMP}})

- <Severity> <概要> (commit `<SHA>`)
- ...

### 凍結項目 (このラウンドで再指摘されたが反映しない)
- <概要> (理由: <凍結理由>)
```

## Step 4: 結果返却

stdout に最終 JSON を 1 行で出力:

```json
{
  "phase_id": "{{PHASE_ID}}",
  "round": {{ROUND}},
  "applied_commits": ["<SHA1>", "<SHA2>", ...],
  "skipped_findings": [{"reason": "...", "summary": "..."}, ...],
  "frozen_recidive_count": <件数>,
  "smoke_test_passed": true,
  "duration_sec": <秒>,
  "next_action": "continue|stop_repo|stop_all"
}
```

---

# 致命停止条件 (subagent 内で判断)

| 条件 | next_action |
|---|---|
| Critical 検出 | `stop_all` |
| smoke test 失敗 | `stop_repo` |
| build 失敗 連続 3 件 | `stop_repo` |
| 凍結項目再指摘 連続 3 件 | `stop_repo` |
| その他 | `continue` |

# 範囲外 finding の扱い

以下は反映せず skip 判定にする (docs/04 scope creep + docs/_review-notes-v0.4-beta-frozen.md):

- 「説明追加・コメント追加」だけ (修正の負債化)
- アーキテクチャ大改修 (= 別 session / 計画書化)
- 既存 design 範囲外 (= 凍結)
- 「外部 framework 対応」(v0.5 は Next.js + Supabase 特化)

skip した finding は `{{REPO_PATH}}/docs/_review-notes-phase{{PHASE_ID}}.md` に追記 (= 後でレビュー)。

# 実行例

```
prompt 入力 (例):
- REPO_NAME: aifcc-workshop
- PHASE_ID: 10101
- ROUND: 1
- REPO_PATH: /Users/5dmgmt/Plugins/aifcc-workshop
- PHASE_FILE: app/workshop/data/phases/course1/phase10101.ts
- ROUND_OUTPUT: /tmp/phase-10101-r1.md
- SMOKE_URL: https://workshop.aifcc.jp/
- TARGET_SHA: <SHA>
- TIMESTAMP: 2026-04-29T10:00:00+09:00
```

# 関連文書

- `docs/03-five-decisive-fixes.md` — Fix 1 (commit pin) / Fix 6 (横断 6 観点)
- `docs/04-convergence-patterns.md` — scope creep / 凍結項目判定
- `docs/_review-notes-v0.4-beta-frozen.md` — 永久機関化パターン (state-of-time 転記禁止)
- `docs/10-multi-repo-phase-audit-loop.md` — 親設計 (本 subagent はその一部)
