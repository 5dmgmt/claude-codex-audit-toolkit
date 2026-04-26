# 01. Claude Code + Codex 監査ループの全体像

## 想定読者

- Claude Code (Anthropic) でランブック・教材・ドキュメントを書いている人
- 書いた成果物を OpenAI Codex CLI (`codex exec` / `codex review`) で品質監査したい人
- 「ラウンドごとに finding が小出しに出続けて終わらない」「3 ラウンド超えるべきか scope cut すべきか判断できない」と悩んでいる人

## 本ツールキットの 3 つの柱

```
[1. 五月雨防止プロンプト v2]
   ↓ Codex に R2 以降必ず冒頭配置
[2. 5 つの決定的対策]
   ↓ ランブック品質を ALL PASS まで持っていく
[3. 収束判定基準]
   → 正常収束 (継続) vs scope creep (停止) を識別
```

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
6. ラウンドごとの finding 件数を 4. の判定基準 (docs/04) で評価
   - 単調減少 → 正常収束として継続
   - 件数停滞 / 矛盾指摘 → scope creep として停止
   ↓
7. ALL PASS or 構造的に改善できないレベルで確定
```

## 期待される結果

このツールキットを適用すると、**多くのケースで 1-3 ラウンドで PASS** に到達します。SIFT Phase C のような構造的に複雑なランブックでも 13 ラウンドで安定収束しました。

逆に、これらを適用しないと:
- 同じ指摘が周回する
- 過去ラウンドで反映済の修正を Codex が再指摘してくる
- 矛盾する指摘 (R6 で「A にすべき」→ R8 で「B にすべき」) が出る
- 5-9 ラウンド回しても収束しない

これらは Codex の問題ではなく、Claude Code 側のプロンプト設計の問題です。

## 次に読むべき文書

1. [`02-anti-drip-prompt-v2.md`](02-anti-drip-prompt-v2.md) — 五月雨防止プロンプト v2 の本文
2. [`03-five-decisive-fixes.md`](03-five-decisive-fixes.md) — 5 つの決定的対策の実装
3. [`04-convergence-patterns.md`](04-convergence-patterns.md) — 収束判定基準
4. [`05-env-lint-checklist.md`](05-env-lint-checklist.md) — 環境系 lint 14 項目 (事前撲滅)

## 実プロジェクトでの実証

このツールキットは AIFCC (`aifcc.jp`) という日本のコミュニティの 4 つの実プロジェクトで実証されました:

- **Workshop** (`workshop.aifcc.jp`): プログラミング基礎教材 / Course 1 ランブック / 4 ラウンドで scope cut → v3.4 確定
- **SIFT** (`sift.aifcc.jp`): AI 仕分けプログラム / Phase C ランブック / 13 ラウンドで ALL PASS
- **RUN** (`run.aifcc.jp`): 運用フェーズプログラム / Course 1-5 監査
- **CPN** (`cpn.aifcc.jp`): CCA-F 試験対策 / 受講開始前の最終磨き上げ

`examples/` に各プロジェクトの抜粋を収録しています。
