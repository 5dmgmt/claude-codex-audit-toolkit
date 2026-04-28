# 3 ケース比較 — Workshop 4R / SIFT 13R / video-subtitler 5R

> 旧ファイル名は `comparison-4r-vs-13r.md` のままですが、内容は **3 ケース比較** に拡張済 (リンク互換性のため名前は維持)。

## 何が違ったか

3 ケースとも v2 系プロンプト設計を適用した監査ですが、**結末** と **運用パターン** が異なります:

- **Workshop Course 1** (ランブック / 教材): 4 ラウンドで scope cut → v3.4 確定
- **SIFT Phase C** (ランブック / 監査): 13 ラウンドで ALL PASS
- **video-subtitler** (コードベース / Whisper+ffmpeg pipeline): 5 周で H/M/L 下降収束 (残課題 2 件)

これは **どれかが失敗** ではなく、**対象の構造的特性と監査系統の違い** です。

## 対比表

| | Workshop Course 1 | SIFT Phase C | video-subtitler |
|---|---|---|---|
| **系統** | ランブック監査 (教材) | ランブック監査 (受講者ジャーニー) | コードベース監査 (Whisper+ffmpeg pipeline) |
| **検査対象** | 教材ランブック (15 phase 構成) | システム構造を含む受講者ジャーニー監査ランブック | 実装コードベース全体 + AUDIT_RUNBOOK.md |
| **1 ラウンド単位** | 1 ファイル (`docs/...md`) | 1 ファイル | 1 commit (リポ全体 / 複数ファイル) |
| **使用 model** | gpt-5.5 xhigh | gpt-5.5 xhigh | gpt-5.4 xhigh (gpt-5.5 xhigh は 19 分 hang あり) |
| **R1 件数 / 周 1 検出** | 40 件 (P1×1+P2×35+P3×4 推定) | 多数 (詳細件数なし) | H4/M4/L2 |
| **R3 件数 / 周 3 検出** | 6 件 | 18 件 | H1/M4/L3 |
| **R4-R5 / 周 4-5** | R4 = 6 件停滞 → scope cut | R4=6 / R5=5 (下降継続) | 周 4 = H1/M6/L3 / 周 5 = H2/M3/L1 |
| **R6+ / 周 6+** | (該当なし) | R6-R12 増減を挟みつつ低位推移 (Phase C runbook 参照) | (5 周で残課題 2 件位置取り) |
| **最終ラウンド** | R4 で scope cut | R13 で ALL PASS | 周 5 で残 M16+L10、次セッション判断 |
| **v2 + Fix 適用** | R2 で部分適用、R3 で完全適用 | R4 で v2 導入、R5+ で 5 fixes 継続、R10-R12 で bypass 4 原則 | Fix 6 (横断 6 観点 ULTRATHINK) **不在のまま 5 周** = 五月雨式運用の反省 |
| **確定形** | v3.4 確定 + R4 6 件全件反映 | ALL PASS 通過 | 残 2 件は次セッション判断 |

## なぜ Workshop は 4R で停滞したか

- R3 → R4 で件数が **6 → 6 に停滞** していた
- R4 の指摘は「過去ラウンドで反映済の方針への別角度からの指摘」「より細かく書けという detail 要求」が中心
- ランブックが既に 800+ 行に膨張しており、これ以上書き足すと受講者が読めない
- 教材手順・可読性中心の指摘構造で、書き物としての細分化に天井があった

→ R4 6 件を **全件反映したうえで「R5 不要」と判断して v3.4 確定**。`_review-notes.md` への転記や `git tag v3.4` は今回ケースでは実施していない (この snippet では「scope cut 検討の典型例」として概念化している)。

## なぜ SIFT は 13R で PASS したか

- R3 → R4 → R5 = 18 → 6 → 5 と **下降傾向継続** (Workshop の「同数停滞」とは異なる)
- 指摘の中身が **実装仕様・構造不備中心** で、対処すれば finding が消える性質
- R10-R12 で dev bypass の構造的機能を後追い反映 (`docs/06` 4 原則は最初から織り込まれていなかった)
- R12 の P2×2 + P3×1 を反映して R13 で ALL PASS

## なぜ video-subtitler は 5 周もかかったか

- **横断 6 観点 ULTRATHINK ([Fix 6](../docs/03-five-decisive-fixes.md#fix-6-反復監査の-1-周目で横断-6-観点-ultrathink-を全部洗う)) を 1 周目に行わなかった** = 五月雨式運用の主因
- 周 2-4 で時間軸不整合 / 並行実行衝突 / 原子性欠如 / パストラバーサル が逐次検出された (これらは Fix 6 6 観点で 1 周目に予防可能だった)
- gpt-5.5 xhigh で 19 分以上 hang する事例が出たため周 1 と 5 で gpt-5.4 xhigh に切替
- 1 周ごとに push したため `_review-notes.md` 等の closure 成果物が散逸 (今後はまとめて 1 commit を推奨)
- 残 M16 (content-only fingerprint が SHA hash でない) + L10 (並行 Phase B output_path 衝突 = last-writer-wins) は次セッションで判断する位置取り

## 判断ポイント

### Workshop と SIFT で停滞解釈が異なる理由

Workshop は R3 → R4 で同数停滞、SIFT は R4 以降の低位推移だけを表面的に見ると一見停滞のように読めますが、SIFT は実際には R3=18 → R4=6 → R5=5 で下降傾向継続です。本質的な差は:

- **Workshop**: R3=6 → R4=6 の **同数停滞** + 反映済方針への別角度指摘 + ランブック膨張限界 → stop
- **SIFT**: R3=18 → R4=6 → R5=5 の **下降傾向継続** + 矛盾指摘なし + 同一 finding 再発なし + 未解決 finding が具体行に紐づく (具体実装の未反映が残っていた) → continue

つまり「停滞解釈」での違いではなく、**Workshop は同数停滞 + 言い換え/膨張、SIFT は下降傾向 + 具体実装未反映** という差でした。

判断材料:
1. **指摘の中身**: Workshop は「角度を変えた言い換え」「detail の細分化」、SIFT は「具体的実装の修正」
2. **件数推移**: Workshop は R3-R4 が同数、SIFT は R3 → R4 → R5 で下降継続
3. **未解決 finding が具体行に紐づくか**: Workshop は「全体的に読みづらい」系、SIFT は「`app/api/foo/route.ts` 行 N の bypass 二重ガード」系
4. **ランブックの読者負荷 / 対処余地**: Workshop は受講者が読める範囲を超えていた、SIFT はまだ実装の隙があり対処すれば消える性質だった

## 教訓

### 1. ラウンド数そのものは判断基準ではない

「3 ラウンド超えたら scope cut」は経験則 / 警戒目安に過ぎません。SIFT のように 13 ラウンドかけて PASS する構造もあります。

### 2. 対象の性質と監査系統で目安が変わる (この 3 ケース観察に基づく)

| 系統 | 対象タイプ | 観察された傾向 |
|---|---|---|
| ランブック監査 (Workshop) | 教材手順・可読性中心 | 数ラウンドで停滞することがある |
| ランブック監査 (SIFT) | 実装仕様・構造不備中心 | より多いラウンドで PASS に到達することがある |
| コードベース監査 (video-subtitler) | Whisper+ffmpeg pipeline | 横断観点 ULTRATHINK 不在で五月雨式 5 周、Fix 6 適用で 2-3 周収束見込 (要検証) |

これは 3 ケースからの観察で、「書き物 vs コード」の二分法や「ラウンド数」の固定目安を一般化するものではありません。

### 3. 件数推移と他条件の複合判定

件数推移だけでなく、現 v2 の収束判定 4 条件を複合で見ます:

- 直近 2-3 ラウンドの総件数が下降傾向
- 矛盾指摘なし
- 同一 finding の再発なし
- 未解決 finding が具体行に紐づく

すべて ✅ なら継続、1 つでも ❌ なら scope cut 検討。Workshop の R4 は「同数停滞 + 反映済方針への別角度指摘」で複数条件が ❌ だったため、SIFT R4 は「下降継続 + 具体実装に紐づく」で全条件 ✅ だったため、判断が分かれました。

### 4. ランブックの行数も判断材料 (教材系の場合)

ランブックが受講者の読める範囲を超えていたら、構造的に scope cut すべきタイミング。Codex は「もっと書け」と言い続けるが、書きすぎると逆効果。実装監査ランブックでも、判断者が読み切れないサイズに膨張したら同様。

### 5. コードベース監査では Fix 6 (横断 6 観点 ULTRATHINK) が必須

video-subtitler 5 周 / 五月雨式運用の主因は **Fix 6 不在で 1 周目に観点を予防的に押さえなかった** ことでした。コードベース監査では `docs/03 Fix 6` の 6 観点 (セキュリティ / 並行性 / データフロー整合性 / 例外伝播 / リソース管理 / エッジケース) を 1 周目で全部洗い、Codex を「答え合わせ / 最終チェック」に格下げするのが推奨パターンです。

ランブック監査でも該当観点 (主にデータフロー整合性 / 例外伝播 / エッジケース) は適用できます。

## 関連文書

- [`docs/01-overview.md`](../docs/01-overview.md) — ランブック監査 vs コードベース監査の 2 系統分岐
- [`docs/03-five-decisive-fixes.md`](../docs/03-five-decisive-fixes.md) — 6 つの決定的対策 (Fix 6 横断観点 ULTRATHINK 含む)
- [`docs/04-convergence-patterns.md`](../docs/04-convergence-patterns.md) — 収束判定基準
- [`workshop-course1-snippet.md`](workshop-course1-snippet.md) — Workshop 4R 詳細 (ランブック / 教材)
- [`sift-phase-c-snippet.md`](sift-phase-c-snippet.md) — SIFT 13R 詳細 (ランブック / 監査)
- [`video-subtitler-snippet.md`](video-subtitler-snippet.md) — video-subtitler 5R 詳細 (コードベース)
