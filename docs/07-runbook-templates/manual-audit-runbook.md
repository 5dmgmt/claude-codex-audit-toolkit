# 手動監査ランブック テンプレート

> Workshop / SIFT / RUN / CPN の 4 リポで運用したランブックを抽象化したテンプレート。

## 使い方

1. 本ファイルを `docs/runbooks/{date}-{project}-manual-audit-runbook.md` にコピー
2. `__PROJECT__` `__SCOPE__` `__SHA__` 等の placeholder を埋める
3. 受講者シミュレーション (terminal A) と教材修正 (terminal B) で並行実行
4. Phase 単位で finding を `_review-notes.md` に蓄積、合格判定で次 Phase へ

---

# __PROJECT__ 手動監査ランブック

- 検査対象: __SCOPE__
- commit: __SHA__ (固定)
- 確定 version: __VERSION__
- 作業日: __DATE__

## 0. 前提

### 0.1 cwd 分離

- Terminal A (受講者): `~/sandbox/__PROJECT__-clone` (clean clone で受講者目線)
- Terminal B (教材修正): `~/Plugins/__PROJECT__` (修正反映)

両方とも絶対パスで `cd` / `git -C` を使う (相対パス禁止)。

### 0.2 dev 環境準備

```bash
# Terminal A (受講者シミュレーション)
git clone https://github.com/5dmgmt/__PROJECT__.git ~/sandbox/__PROJECT__-clone
cd ~/sandbox/__PROJECT__-clone
git checkout __SHA__
op inject -i .env.tpl -o .env.local --force
npm install
PORT=3001 npm run dev
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
[受講者目線] Terminal A で Phase X を完走
    ↓
[finding 抽出] 違和感を _review-notes.md に追記
    ↓
[教材修正] Terminal B で修正反映 → commit
    ↓
[Codex 監査] 修正後 SHA で codex exec 実行
    ↓
[判定] PASS なら次 Phase / FAIL なら再修正
```

## 5. 必須ゲート (Phase 進行条件)

各 Phase の合格条件:

- [ ] P1 残ゼロ (例外不可)
- [ ] 未承認 P2 残ゼロ (承認済 P2 は `_review-notes.md` の例外承認表に記録)
- [ ] paste 5 軸全部 ✅
- [ ] Viewport 3 軸全部 ✅
- [ ] Codex 監査で当該 Phase に関する finding なし

5 つ全部 ✅ で次 Phase 進行。

## 6. _review-notes.md フォーマット

```markdown
# __PROJECT__ Phase X review notes

## P1 finding
- (なし)

## P2 finding (未承認)
- (なし)

## P2 finding (承認済 — 例外として確定)
| ID | 違和感 | 承認理由 | 承認日 |
|---|---|---|---|
| F-R3-005 | XXX | scope 外 / 次 version で対応 | 2026-04-26 |

## P3 finding
- F-R3-001 用語揺れ「phase」「段階」(Phase 7 で統一予定)
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

- [`02-anti-drip-prompt-v2.md`](../02-anti-drip-prompt-v2.md) — 五月雨防止プロンプト v2
- [`03-five-decisive-fixes.md`](../03-five-decisive-fixes.md) — 5 つの決定的対策
- [`04-convergence-patterns.md`](../04-convergence-patterns.md) — 収束判定基準
- [`05-env-lint-checklist.md`](../05-env-lint-checklist.md) — 環境系 lint 14 項目
- [`06-dev-bypass-design.md`](../06-dev-bypass-design.md) — dev bypass 4 原則
- [`codex-audit-prompt.txt`](codex-audit-prompt.txt) — Codex 監査プロンプトテンプレート
