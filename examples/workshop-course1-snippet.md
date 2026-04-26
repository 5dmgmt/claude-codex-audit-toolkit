# Workshop Course 1 ランブック — 4 ラウンドで scope cut → v3.4 確定

## 概要

AIFCC Workshop プログラミング基礎教材 (Course 1, 15 phase) の手動監査ランブックを Codex で 4 ラウンド回し、v3.4 で scope cut 確定したケース。

## ラウンドごとの推移

| Round | P1 | P2 | P3 | 件数 | 五月雨防止 v2 | コメント |
|---|---|---|---|---|---|---|
| R1 | 1 | 35 | 4 | 40 件 | 未導入 | baseline |
| R2 | 0 | 10 | 3 | 13 件 (-67%) | 部分適用 | 大幅減 |
| R3 | 0 | 5 | 1 | 6 件 (-54%) | 完全適用 | 減衰加速 |
| R4 | 0 | 4 | 2 | 6 件 (停滞) | 完全適用 | **scope cut 判断** |

## R1 → R2 で何が起きたか

R1 (40 件) の指摘の多くは、五月雨防止 v2 を導入しただけで R2 で消えました。

具体的には:
- 「同型の問題が 5 箇所にある」を 1 件としてまとめていた指摘 → 5 件として全箇所列挙されたので、R1 の 1 件 → R2 で 0 件に減った (網羅されたので再指摘されない)
- 「角度を変えた言い換え」が 3-4 件あったのが消えた

## R2 → R3 で何が起きたか

5 つの決定的対策 (commit pin / canonical baseline / 独立変数 fail-fast / BSD sed / dotenv) を全部織り込んで R3 投入。再現性系・環境系の defect が消えました。

## R4 で件数停滞 = scope cut

R3 (6 件) → R4 (6 件) で件数停滞。中身を見ると:
- R3 で反映した方針への「別角度からの指摘」が増えていた
- 「より細かく書けば改善」系の指摘が増えていた (粒度が粗くなる方向ではなく、更に細かい detail を要求)
- ランブックがすでに 800+ 行に膨張しており、これ以上書き足すと受講者が読めない

これは [`04-convergence-patterns.md`](../docs/04-convergence-patterns.md) の **scope creep パターン 1 + パターン 4** に該当。v3.4 で確定終了が正解と判断しました。

## 確定後の処理

1. ランブック冒頭に「v3.4 確定 / Codex 4 ラウンドで scope cut 判定 / これ以降の Codex 監査は scope creep」と明記
2. R4 で出た 6 件のうち、構造的に対応すべき 2 件を「将来検討事項」として `_review-notes.md` に転記
3. 残り 4 件は「scope 外 / 次 version で対応」として例外承認表に記録
4. `git tag v3.4` で確定 commit に tag を打つ

## 学び

- **R3 までで finding が単調減少していたら、R4 で停滞しても v2 + 5 fixes は機能している証拠**。停滞の原因は Codex の粗さではなく、ランブック側の構造的限界
- 「4 ラウンドで scope cut」は Workshop ランブックの構造的特性 (15 phase × 16 要素 = 240 母数) によるもの。SIFT のように 13 ラウンドかかる構造もある
- ランブックの行数が膨張しすぎると、Codex の指摘がさらに細かく刻まれて永久に終わらない。**受講者が読める範囲** が物理的限界

## 関連文書

- [`docs/04-convergence-patterns.md`](../docs/04-convergence-patterns.md) — 収束判定基準
- [`sift-phase-c-snippet.md`](sift-phase-c-snippet.md) — 13 ラウンドで ALL PASS した対照ケース
- [`comparison-4r-vs-13r.md`](comparison-4r-vs-13r.md) — 2 ケースの比較分析
