# SIFT Phase C ランブック — 13 ラウンドで ALL PASS

## 概要

AIFCC SIFT (AI 仕分けプログラム) の Phase C 監査ランブックを Codex で 13 ラウンド回し、R13 で ALL PASS 到達したケース。

## ラウンドごとの推移

| Round | P1 | P2 | P3 | 件数 | 五月雨防止 v2 | コメント |
|---|---|---|---|---|---|---|
| R1 | 0 | 多数 | - | - | 未導入 | baseline |
| R2 | 0 | 多数 | - | - | 未導入 | 構造調整 |
| R3 | 0 | 13 | 5 | 18 件 | 未導入 | 混乱期 (矛盾指摘 cascade) |
| R4 | 0 | 5 | 1 | 6 件 | **v2 導入** | 大幅減 (P2: 13→5) |
| R5 | 0 | 4 | 1 | 5 件 | v2 + 5 fixes | 減衰継続 |
| R6 | 0 | 3 | 0 | 3 件 | v2 + 5 fixes | 減衰継続 |
| R7-R12 | 0 | 着実減少 | - | - | v2 継続適用 | dev bypass 反映 |
| R13 | 0 | 0 | 0 | **ALL PASS** | v2 + 5 fixes + bypass 4 原則 | 安定収束 |

## 何が 13 ラウンドかかったか

SIFT は構造的に複雑なシステム (AI 仕分け / DB / 認証 / 受講者ジャーニー / dev bypass) で、検査対象が広大。

特に R7-R12 で時間がかかったのは:
- **dev bypass の実装** で R10-R12 を消費 (P1+P2 を都合 2 ラウンドで反映)
- bypass 4 原則 ([`06-dev-bypass-design.md`](../docs/06-dev-bypass-design.md)) を最初から織り込んでいなかったため、後から作り直しが発生

## R3 → R4 の劇的減少 (五月雨防止 v2 導入)

R3 (18 件) → R4 (6 件) は v2 導入だけで -67%。R3 の指摘の大半は:
- 同じ違和感の言い換え (3-4 件)
- 過去ラウンドで反映済方針への再指摘 (3-4 件)
- 同型問題の集約抜け (3-4 件)

これらは v2 の 4 行ブロックを冒頭配置するだけで R4 で消えました。

## R13 で ALL PASS — 何が決め手だったか

R13 で ALL PASS した直接の決め手は **dev bypass 4 原則の R12 反映**:

- 二重ガード (NODE_ENV + ENABLE_DEV_AUTH_BYPASS)
- read-only 限定 (write は no-op)
- systemRole=USER 固定
- `if (!userId)` → `=== null` 比較

これにより R12 まで 2 ラウンド連続で出ていた P1×3 / P2×4 が一気にゼロ化。R13 では他軸の指摘もすべて反映済で ALL PASS に到達しました。

## 学び

- **「3 ラウンド超で scope cut」はルールではない**。SIFT のように構造的に複雑な対象は 13 ラウンドかかる場合がある
- 判断基準は **件数の単調減少 + 矛盾指摘なし + 粒度の細かさ**。ラウンド数そのものではない
- dev bypass のような複雑な機能は **最初から 4 原則を織り込む** 方が、後から作り直すよりラウンド数を 5-6 削減できる
- R3 までで finding 件数が二桁台に高止まりしていても、v2 + 5 fixes を導入すれば R4 で大幅減できる

## 比較

| | Workshop Course 1 | SIFT Phase C |
|---|---|---|
| 結果 | 4R で scope cut (v3.4 確定) | 13R で ALL PASS |
| 検査対象 | 15 phase × 16 要素 = 240 母数 | dev bypass 含む構造的システム |
| 主な減衰要因 | 五月雨防止 v2 + 5 fixes | v2 + 5 fixes + bypass 4 原則 |
| 停止理由 | 件数停滞 + ランブック膨張限界 | 全 finding 反映完了 |

詳細は [`comparison-4r-vs-13r.md`](comparison-4r-vs-13r.md) 参照。

## 関連文書

- [`docs/04-convergence-patterns.md`](../docs/04-convergence-patterns.md) — 収束判定基準
- [`docs/06-dev-bypass-design.md`](../docs/06-dev-bypass-design.md) — dev bypass 4 原則
- [`workshop-course1-snippet.md`](workshop-course1-snippet.md) — 4 ラウンドで scope cut した対照ケース
