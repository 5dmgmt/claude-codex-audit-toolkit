# 01. Claude Code + Codex 監査ループの全体像

## 想定読者

- Claude Code (Anthropic) でランブック・教材・ドキュメントを書いている人
- 書いた成果物を OpenAI Codex CLI (`codex exec` / `codex review`) で品質監査したい人
- 「ラウンドごとに finding が小出しに出続けて終わらない」「3 ラウンド超えるべきか scope cut すべきか判断できない」と悩んでいる人

## 本ツールキットの 3 つの柱

```
[1. 五月雨防止プロンプト v2 (実走証拠ベース)]
   ↓ 1 ラウンド = 1 ファイル + 4 行ブロック + 過去反映済リスト 30+ 蓄積
[2. 5 つの決定的対策]
   ↓ ランブック品質の再現性・決定性を高め、ALL PASS または妥当な scope cut まで持っていく
[3. 収束判定基準]
   → 正常収束 (継続) vs scope creep (停止) を識別
```

> 旧 v2 (deprecated) で推奨していた「7 要素重圧テンプレ (全行 enumerate / mandatory セクション / 3 段階構造 / 全カテゴリ均等深さ含む)」は Codex CLI 0.125.0 で tool ループに陥ることが判明したため廃止しました。詳細は [`08-known-pitfalls.md`](08-known-pitfalls.md) 参照。

## 役割分担

| ツール | 役割 |
|---|---|
| **Claude Code** | ランブック・教材・ドキュメントの起案・修正・編集 |
| **Codex CLI** | 独立した第三者視点でランブック品質を監査 (gpt-5.5 + xhigh) |
| **本ツールキット** | 両者の連携を「五月雨」させずに安定収束させる運用パターン |

## 典型的なフロー

```
1. Claude Code でランブック draft v1 を書く
   ↓
2. 環境系 lint チェックリスト (14 項目 / docs/05) で事前撲滅
   ↓
3. Codex で R1 監査 (五月雨防止プロンプト v2 / docs/02 を冒頭配置)
   ↓
4. R1 finding 反映 → ランブック v2
   ↓
5. Codex で R2 監査 (R1 反映を pre-condition として受け入れる)
   ↓
6. ラウンドごとの finding 件数 + 4 条件 (下降傾向 / 矛盾指摘なし / 同一 finding 再発なし / 未解決 finding が具体行に紐づく) を docs/04 で評価
   - 全条件 ✅ → 正常収束として継続
   - 2 ラウンド連続停滞 / 注記なき矛盾 / 同一 finding 再発 / 未解決 finding が具体行に紐づかない or 抽象的 finding 増加 → scope creep として scope cut 検討
   ↓
7. ALL PASS or scope cut として確定
```

## 期待される結果

このツールキットを適用すると、**短いラウンド数で PASS または妥当な scope cut の確定に到達しやすくなる** という仮説に基づいて運用しています (具体的なラウンド数は対象により大きく異なる)。

明示できる実走実証は次の 2 ケース:
- SIFT Phase C ランブック: 13 ラウンドで ALL PASS
- Workshop Course 1 ランブック: 4 ラウンドで scope cut

逆に、これらを適用しないと **数ラウンド以上停滞しうる** 典型症状:
- 同じ指摘が周回する
- 過去ラウンドで反映済の修正を Codex が再指摘してくる
- 矛盾する指摘 (R6 で「A にすべき」→ R8 で「B にすべき」) が出る

主因は **Codex 本体の良否ではなく、プロンプト設計・ランブック構造・監査基盤の決定性不足** にあります。

## 次に読むべき文書

1. [`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) — 五月雨防止プロンプト v2 の本文
2. [`03-five-decisive-fixes.md`](03-five-decisive-fixes.md) — 5 つの決定的対策の実装
3. [`04-convergence-patterns.md`](04-convergence-patterns.md) — 収束判定基準
4. [`05-env-lint-checklist.md`](05-env-lint-checklist.md) — 環境系 lint 14 項目 (事前撲滅)

## 実プロジェクトでの運用と実証

このツールキットは AIFCC (`aifcc.jp`) コミュニティの 4 つの実プロジェクトで運用しています。**運用経験は 4 プロジェクト、公開できる数値実証は 2 ケース** です:

| プロジェクト | 運用範囲 | 公開数値 |
|---|---|---|
| Workshop (`workshop.aifcc.jp`) | プログラミング基礎教材 / Course 1 ランブック | **4 ラウンドで scope cut → v3.4 確定 (数値実証あり)** |
| SIFT (`sift.aifcc.jp`) | AI 仕分けプログラム / Phase C ランブック | **13 ラウンドで ALL PASS (数値実証あり)** |
| RUN (`run.aifcc.jp`) | 運用フェーズプログラム / Course 1-5 監査 | 適用中 / 数値未公開 |
| CPN (`cpn.aifcc.jp`) | CCA-F 試験対策 / 受講開始前の最終磨き上げ | 適用中 / 数値未公開 |

`examples/` には Workshop 4R / SIFT 13R の抜粋と比較分析を収録しています (RUN / CPN の抜粋は未収録)。
