# 手動監査ランブック テンプレート

> Workshop / SIFT / RUN / CPN の 4 リポで運用したランブックを抽象化したテンプレート。
>
> **共通部分**: cwd 分離 / Phase 単位フロー / 必須ゲート / 横断観点。
> **プロジェクト別に差し替える部分**: 名前 / repo URL / clone path / package manager / dev コマンド / Phase 数 / 母数。下の placeholder 一覧で明示しています。

## 使い方

1. 本ファイルを `docs/runbooks/__DATE__-__PROJECT_SLUG__-manual-audit-runbook.md` にコピー
2. 下記の placeholder を全て埋める
3. 受講者シミュレーション (terminal A) と教材修正 (terminal B) で並行実行
4. Phase 単位で finding を `_review-notes.md` に蓄積、合格判定で次 Phase へ

### Placeholder 一覧

| Placeholder | 意味 | 例 |
|---|---|---|
| `__PROJECT_NAME__` | プロジェクト表示名 (見出し用) | `Workshop Course 1` |
| `__PROJECT_SLUG__` | ファイル名 / ディレクトリ用 slug | `workshop-course1` |
| `__REPO_URL__` | clone 用 URL | `https://github.com/5dmgmt/aifcc-workshop.git` |
| `__CLONE_DIR__` | 受講者シミュレーション用 clone 先 (絶対パス) | `$HOME/sandbox/workshop-clone` |
| `__SOURCE_DIR__` | 教材修正用ローカル repo (絶対パス) | `$HOME/Plugins/aifcc-workshop` |
| `__SCOPE__` | 監査対象範囲 (Phase 範囲 / ファイル群) | `Course 1 全 15 Phase` |
| `__BASE_SHA__` | 監査開始時の commit SHA (Terminal A の checkout 先) | `abc1234` |
| `__CURRENT_SHA__` | 現ラウンドで Codex に渡す commit SHA (修正後に更新) | `def5678` |
| `__VERSION__` | 確定 version 名 | `v3.4` |
| `__DATE__` | 作業日 (JST) | `2026-04-27` |
| `__INSTALL_CMD__` | 依存インストールコマンド | `npm install` / `pnpm install` |
| `__DEV_CMD__` | dev サーバー起動コマンド | `npm run dev` |
| `__ENV_SETUP_CMD__` | env 準備コマンド | `op inject -i .env.tpl -o .env.local --force` |
| `__PORT__` | dev サーバー port | `3001` |

---

# __PROJECT_NAME__ 手動監査ランブック

- 検査対象: __SCOPE__
- 開始 commit: __BASE_SHA__ (Terminal A の checkout 先)
- 現ラウンド commit: __CURRENT_SHA__ (Codex 監査の対象 SHA / 修正反映ごとに更新)
- 確定 version: __VERSION__
- 作業日: __DATE__

## 0. 前提

### 0.1 cwd 分離

- Terminal A (受講者): `__CLONE_DIR__` (clean clone で受講者目線)
- Terminal B (教材修正): `__SOURCE_DIR__` (修正反映)

両方とも絶対パス / `$HOME` 展開で `cd` / `git -C` を使う (相対パス・unquoted `~` は禁止)。

### 0.2 dev 環境準備

```bash
# Terminal A (受講者シミュレーション) — 初回のみ
git clone __REPO_URL__ __CLONE_DIR__
cd __CLONE_DIR__
git checkout __BASE_SHA__
__ENV_SETUP_CMD__
__INSTALL_CMD__
PORT=__PORT__ __DEV_CMD__

# 各 Phase 修正反映後 (Terminal B でランブック修正 + commit / push 後)
cd __CLONE_DIR__
git fetch && git checkout __CURRENT_SHA__
PORT=__PORT__ __DEV_CMD__
```

`.env.local` で `ENABLE_DEV_AUTH_BYPASS=true` を有効化する場合は [`06-dev-bypass-design.md`](../06-dev-bypass-design.md) の 4 原則を満たすこと。

## 1. 検査軸 (3 ティア構造)

### P1 (致命的 — 即修正)

- 認証 / 権限漏洩
- データ破壊
- 公式仕様違反 (モデル名 / API 仕様)
- ビルド / 起動失敗

### P2 (重要 — 確定前修正)

- フィールド整合違反
- 再現性欠如 (commit 動く / port 競合 / BSD 非互換)
- PASS-FAIL 判定の曖昧さ
- scope 逸脱

### P3 (改善 — 余裕があれば)

- 用語揺れ
- 微妙な表記改善
- コメント / docstring 改善

## 2. paste 5 軸 (受講者の貼り付け検証)

受講者が prompt をコピペする箇所では、5 軸全部で検証:

1. **innerText 完全一致** (canonical baseline)
2. **改行コード** (`\n` / `\r\n` の統一)
3. **末尾空白** (trailing whitespace)
4. **見えない文字** (zero-width space / nbsp)
5. **エンコーディング** (UTF-8 BOM の有無)

[`03-five-decisive-fixes.md` Fix 2](../03-five-decisive-fixes.md#fix-2-canonical-baseline-dom-api-の選定統一) 参照。

## 3. Viewport 3 軸 (UI ジャーニー)

UI を操作する箇所では、3 viewport で検証:

1. **mobile** (375x667 / iPhone SE)
2. **tablet** (768x1024 / iPad)
3. **desktop** (1280x800)

各 viewport で「読める / 操作できる / 崩れない」の 3 観点。

## 4. Phase 単位の検査フロー

各 Phase で以下を実行:

```
[受講者目線] Terminal A で Phase X を完走 (__BASE_SHA__ または前 Phase 確定 SHA)
    ↓
[finding 抽出] 違和感を _review-notes.md に追記
    ↓
[教材修正] Terminal B で修正反映 → commit + push (新 SHA 取得)
    ↓
[新 SHA 同期] Terminal A で git fetch + git checkout __CURRENT_SHA__
    ↓
[Codex 監査] scripts/codex-audit-prompt-gen.sh 経由で codex exec 実行
    ↓
[判定] PASS なら次 Phase / FAIL なら再修正 (本 Phase の R2 として再ループ)
```

### Codex 監査ステップの実行例

```bash
# (a) Terminal B (教材修正) で監査対象 SHA を取得
cd __SOURCE_DIR__
TARGET_SHA=$(git rev-parse HEAD)

# (b) Terminal A (受講者シミュレーション) を __CURRENT_SHA__ に同期
git -C __CLONE_DIR__ fetch
git -C __CLONE_DIR__ checkout "$TARGET_SHA"

# (c) Terminal A と Terminal B の SHA が一致していることを assert
test "$(git -C __CLONE_DIR__ rev-parse HEAD)" = "$(git -C __SOURCE_DIR__ rev-parse HEAD)" \
  || { echo "FAIL: clone と source の SHA が不一致"; exit 1; }

# (d) プロジェクト固有の prompt template を用意 (既定 codex-audit-prompt.txt の {本ランブック固有...} を埋めたもの)
PROMPT_TEMPLATE_PATH="docs/runbooks/__DATE__-__PROJECT_SLUG__-codex-prompt-template.txt"
test -f "$PROMPT_TEMPLATE_PATH" \
  || { echo "FAIL: $PROMPT_TEMPLATE_PATH が無い (プロジェクト固有 5-7 軸を埋めたテンプレを作る)"; exit 1; }

# (e) generator で prompt 生成
scripts/codex-audit-prompt-gen.sh \
  --runbook docs/runbooks/__DATE__-__PROJECT_SLUG__-manual-audit-runbook.md \
  --runbook-name "__PROJECT_NAME__ 手動監査ランブック" \
  --prev-findings "{R1 で反映済の方針 30+ 項目を蓄積}" \
  --template "$PROMPT_TEMPLATE_PATH" \
  > /tmp/codex-prompt.txt

# (f) 未解決 placeholder と軸数の preflight
grep -nE '\{[^}]*\}|__[A-Z_]+__' /tmp/codex-prompt.txt \
  && { echo "FAIL: prompt に未解決 placeholder が残っている"; exit 1; } || true

codex exec -s read-only -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  --output-last-message /tmp/codex-result.md \
  "$(cat /tmp/codex-prompt.txt)" < /dev/null
```

`scripts/codex-audit-prompt-gen.sh` は内部で `sed '/^##/d'` でテンプレ冒頭の `##` コメントを除去し、4 placeholder を bash parameter expansion で置換します ([`docs/02-anti-drip-prompt-v2.md`](../02-anti-drip-prompt-v2.md) 参照)。

## 5. 必須ゲート (Phase 進行条件)

各 Phase の合格条件:

- [ ] **P1 残ゼロ** (例外不可) / 証跡: Codex 監査出力 + `_review-notes.md` の P1 セクション空
- [ ] **未承認 P2 残ゼロ** / 証跡: 承認済 P2 は `_review-notes.md` の例外承認表に ID / 承認者 / 承認日 / 理由を記録
- [ ] **Codex 監査で P1 / 未承認 P2 がゼロ** / 証跡: `/tmp/codex-result.md` の総合判定行 (P3 finding は記録のみで進行可)
- [ ] **paste 検証**: 該当する場合は 5 軸検証ログ / canonical baseline スクショ / `diff orig clip` の出力。非該当の場合は `_review-notes.md` に `N/A: 理由` を記録
- [ ] **Viewport 検証**: 該当する場合は 3 viewport 各 1 枚以上のスクショ。非該当の場合は `_review-notes.md` に `N/A: 理由` を記録
- [ ] **承認**: ランブック設定 (確定 version 列の責任者) が承認者として承認 / 承認日: YYYY-MM-DD JST

6 項目全部 ✅ + 証跡記録で次 Phase 進行。**P3 は記録のみで進行可** (P3 finding 残っていても進行できる)。

## 6. _review-notes.md フォーマット

```markdown
# __PROJECT_NAME__ Phase X review notes

## P1 finding
- (なし)

## P2 finding (未承認)
- (なし)

## P2 finding (承認済 — 例外として確定)
| ID | 違和感 | 承認理由 | 承認者 | 承認日 |
|---|---|---|---|---|
| F-R3-005 | XXX | scope 外 / 次 version で対応 | __APPROVER__ | 2026-04-26 |

## P3 finding
- F-R3-001 用語揺れ「phase」「段階」(Phase 7 で統一予定)

## 将来検討事項 (scope cut 時)
| ID | finding | 次 version 判断 | 転記日 |
|---|---|---|---|
| F-R4-002 | XXX | __NEXT_VERSION__ で対応 | 2026-04-26 |
```

## 7. 横断検査 3 観点

Phase 個別ではなく全体を見て確認:

- **A. 整合性**: ランブック全体での用語 / 数値 / 命名一貫性
- **B. 網羅性**: 受講者が引っかかる箇所がランブックでカバーされているか
- **C. 可読性**: 受講者が読み飛ばさず理解できる構造か

## 8. commit 粒度

1 Phase = 1 commit を原則:

```
feat(phase10501): paste 検証ロジック追加

- innerText canonical baseline 採用
- 改行コード統一を verify ステップ追加
- F-R3-002 / F-R3-007 反映
```

複数 Phase をまとめると Codex 監査時に diff が大きすぎて指摘が散らかる。

## 9. 着手スケジュール

| Phase | 想定所要 | 実所要 | 担当 |
|---|---|---|---|
| Phase 1 | 30 min | | |
| Phase 2 | 45 min | | |
| ... | | | |

## 10. 確定 (scope cut) 判定

[`04-convergence-patterns.md`](../04-convergence-patterns.md) の判定基準で:

- 正常収束 → 継続
- scope creep → __VERSION__ で確定、未対応 finding を「将来検討事項」として `_review-notes.md` に転記

## 関連文書

> 本テンプレを `docs/runbooks/...` にコピーして使う前提なので、コピー後の相対リンクは以下の形になります:

- [`02-anti-drip-prompt-v2.md`](../../07-runbook-templates/../02-anti-drip-prompt-v2.md) — 五月雨防止プロンプト v2 (コピー後は `../02-anti-drip-prompt-v2.md` ではなく対象 repo 構造に合わせて調整)
- [`03-five-decisive-fixes.md`](../../07-runbook-templates/../03-five-decisive-fixes.md) — 5 つの決定的対策
- [`04-convergence-patterns.md`](../../07-runbook-templates/../04-convergence-patterns.md) — 収束判定基準
- [`05-env-lint-checklist.md`](../../07-runbook-templates/../05-env-lint-checklist.md) — 環境系 lint 14 項目
- [`06-dev-bypass-design.md`](../../07-runbook-templates/../06-dev-bypass-design.md) — dev bypass 4 原則
- [`codex-audit-prompt.txt`](../07-runbook-templates/codex-audit-prompt.txt) — Codex 監査プロンプトテンプレート (コピー後は対象 repo の同テンプレを参照)
