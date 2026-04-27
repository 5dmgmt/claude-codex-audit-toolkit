# Workshop Course 1 ランブック — 4 ラウンドで scope cut → v3.4 確定

## 概要

AIFCC Workshop プログラミング基礎教材 (Course 1, 15 phase) の手動監査ランブックを Codex で 4 ラウンド回し、v3.4 で scope cut 確定したケース。

## ラウンドごとの推移

> 出典: `aifcc-workshop/docs/runbooks/2026-04-26-COURSE1-MANUAL-AUDIT-RUNBOOK.md` で裏取り可能なのは R1=40 / R2=P2×10/P3×3 / R3=P2×5/P3×1 / R4=P2×4/P3×2。R1 の P1×1 / P2×35 / P3×4 内訳は当時のラウンドログから抽出した推定値で、runbook 本体には総数のみ記録。

| Round | P1 | P2 | P3 | 件数 | 五月雨防止 v2 | コメント |
|---|---|---|---|---|---|---|
| R1 | 1 (推定) | 35 (推定) | 4 (推定) | 40 件 | 未導入 | baseline (内訳は当時ログ由来) |
| R2 | 0 | 10 | 3 | 13 件 (-67%) | 部分適用 | 大幅減 |
| R3 | 0 | 5 | 1 | 6 件 (-54%) | 完全適用 | 減衰加速 |
| R4 | 0 | 4 | 2 | 6 件 (停滞) | 完全適用 | **R4 6 件全件反映 + R5 不要として v3.4 確定** |

## R1 → R2 で何が起きたか

R1 (40 件) の指摘の多くは、五月雨防止 v2 を導入しただけで R2 で 13 件に減少 (-67%)。具体例 (当時ログ由来 / runbook には未記録):
- 「同型の問題が 5 箇所にある」を 1 件としてまとめていた指摘 → 5 件として全箇所列挙されたので、R1 の 1 件 → R2 で 0 件に減った (網羅されたので再指摘されない) — 一因と見られる
- 「角度を変えた言い換え」が 3-4 件あったのが消えた — 一因と見られる

## R2 → R3 で何が起きたか

5 つの決定的対策 (commit pin / canonical baseline / 独立変数 fail-fast / BSD sed / dotenv) を全部織り込んで R3 投入。再現性系・環境系の defect が消えました。

## R4 で件数停滞 → 全件反映 + scope cut

R3 (6 件) → R4 (6 件) で件数停滞。中身を見ると:
- R3 で反映した方針への「別角度からの指摘」が含まれていた
- 「より細かく書けば改善」系の detail 細分化要求が含まれていた
- ランブックが 800+ 行に膨張しており、これ以上書き足すと受講者が読めない範囲に達した (判断材料)

これらを根拠に「R4 6 件停滞 + 反映済方針への別角度指摘 + ランブック膨張」を観察し、[`04-convergence-patterns.md`](../docs/04-convergence-patterns.md) の収束判定 4 条件のうち複数が ❌ となったため、**今回は scope cut が妥当と判断**。R5 を回さずに v3.4 で確定終了しました。

## 確定後の処理

1. R4 で出た 6 件を全件反映 (Workshop の場合、未対応 finding を残さない方針で全件反映を選択)
2. ランブック冒頭に「v3.4 確定 / Codex 4 ラウンドで scope cut 判定 / これ以降の Codex 監査は scope creep」と明記
3. 確定 commit を push (本ケースでは git tag は付けず、ランブック冒頭明記で確定状態を表現)

> 別ケースで未対応 finding を残す場合の標準手順は [`docs/04-convergence-patterns.md`](../docs/04-convergence-patterns.md) の「scope cut の実行手順」参照 (`_review-notes.md` への転記 → ランブック明記 → commit → tag の順)。

## 学び

- R3 までで finding が下降していたら、R4 で停滞しても v2 + 5 fixes が一定機能している示唆。Workshop の場合は停滞要因がランブック側の構造的限界 (教材手順・可読性の細分化天井) にあった (この 1 ケースの観察)
- 「4 ラウンドで scope cut」は Workshop ランブック今回ケースの結果。教材手順・可読性中心の対象では数ラウンドで停滞することがあるという 1 つの観察 (一般化はしない)
- 「受講者が読める範囲」は測定値ではなく判断材料 — ランブックの行数が膨張しすぎると Codex の指摘がさらに細かく刻まれる傾向がある

## 関連文書

- [`docs/04-convergence-patterns.md`](../docs/04-convergence-patterns.md) — 収束判定基準
- [`sift-phase-c-snippet.md`](sift-phase-c-snippet.md) — 13 ラウンドで ALL PASS した対照ケース
- [`comparison-4r-vs-13r.md`](comparison-4r-vs-13r.md) — 2 ケースの比較分析
