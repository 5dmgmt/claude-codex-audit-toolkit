# video-subtitler — 5 周で収束した **コードベース監査** の例

## 概要

`5dmgmt/video-subtitler` (Whisper + ffmpeg を使った字幕生成パイプライン) を Codex で 5 周監査し、High/Medium/Low 件数が下降して収束したケース。本ツールキットの 2 つの対照ケース (Workshop 4R / SIFT 13R) はどちらも **ランブック監査** だったが、本ケースは **コードベース監査** で運用パターンが異なる。

## ラウンドごとの推移

> 出典: claude-memory `video_subtitler_audit.md` (commit `2c906df`)。

| 周 | model | 検出 (H / M / L) | 完了 commit |
|---|---|---|---|
| 1 | gpt-5.4 xhigh | 4 / 4 / 2 | `3c4d5d7` |
| 2 | gpt-5.5 xhigh | 2 / 3 / 3 | `11d5c9a` |
| 3 | gpt-5.5 xhigh | 1 / 4 / 3 | `ce143f8` |
| 4 | gpt-5.5 xhigh | 1 / 6 / 3 | `b44ebff` |
| 5 | gpt-5.4 xhigh | 2 / 3 / 1 | `bb41eb1` |

5 周目で High2 + M14/M15 を反映済。残課題は M16 (content-only fingerprint が size+mtime_ns で SHA hash ではない portability 問題) と L10 (並行 Phase B の output_path 衝突 = last-writer-wins) の 2 件で、次セッションで判断する位置取り。

## なぜ 5 周もかかったか — 反省

**周回ごとに新規構造的バグが発見された** こと自体が問題で、これらは観点を最初に列挙していれば 1 周目で気づけたものでした:

- 周 2-4 で発見: 時間軸不整合 / 並行実行衝突 / 原子性欠如 / パストラバーサル
- 周 1 では「動くコード」優先で書いた結果、横断的観点を後追いで洗うことに

CODEX 4 分 × 5 周 + push 5 回の **五月雨式運用** になり、運用上の反省として claude-memory に `feedback_audit_workflow.md` を記録 ([詳細](#feedback-反映)) 。

## ランブック監査ケースとの対比

| 軸 | Workshop / SIFT (ランブック監査) | video-subtitler (コードベース監査) |
|---|---|---|
| 1 ラウンドの単位 | 1 ファイル (ランブック .md) | 1 commit (リポ全体 / 複数ファイル) |
| 監査対象の変動性 | 文書 / 静的 | 実装コード / 動的 |
| Codex の役割 | 文書整合 / 表現決定性 / 再現性 | コード品質 / セキュリティ / 並行性 / 例外伝播 |
| 推奨 model | `gpt-5.5 xhigh` | `gpt-5.4 xhigh` (大規模コード監査では gpt-5.5 xhigh は 19 分超の hang リスクあり) |
| 必須オプション | `-s read-only` | `-s read-only` + `--skip-git-repo-check` |
| 重要な事前準備 | 環境系 lint 14 項目撲滅 (`docs/05`) | **横断 6 観点 ULTRATHINK** (`docs/03 Fix 6`) |
| 出力サイズ | 数 KB-30 KB | 100 KB+ も発生 (tail で取得) |

## 教訓 (ツールキット反映)

### Fix 6: 反復監査の 1 周目で横断 6 観点 ULTRATHINK を全部洗う

video-subtitler の 5 周式運用は、周回ごとに新規バグが出た = 「横断観点を初回に列挙していなかった」ことが直接の原因でした。本ケースから抽出した **Fix 6 (横断 6 観点 ULTRATHINK)** を [`docs/03-five-decisive-fixes.md`](../docs/03-five-decisive-fixes.md#fix-6-反復監査の-1-周目で横断-6-観点-ultrathink-を全部洗う) に追加しました。

6 観点:
1. **セキュリティ** (注入 / traversal / 権限)
2. **並行性** (race / lock / atomicity)
3. **データフロー整合性** (時間軸 / スキーマ / 依存関係)
4. **例外伝播** (外部ライブラリ / OS エラー / ユーザー入力)
5. **リソース管理** (一時ファイル / メモリ / ハンドル)
6. **エッジケース** (空入力 / 境界値 / nan/inf / 超巨大)

これを 1 周目に自己 ULTRATHINK で全部洗い、初回修正で予防的に押さえる。CODEX 監査は **「答え合わせ / 最終チェック」** に格下げする。

### モデル選択の運用知見

| 監査対象 | 推奨 model | 理由 |
|---|---|---|
| ランブック (静的文書) | `gpt-5.5 xhigh` | 文書整合 / 表現決定性に強く、4-10 分で完走 |
| コードベース (大規模実装) | `gpt-5.4 xhigh` | gpt-5.5 xhigh で 19 分以上 hang する事例あり / gpt-5.4 は 4-5 分実績 |

`--skip-git-repo-check` はコードベース監査では必須 (git 状態で挙動が変わるのを避ける)。

### 1 周ごとに push しない / まとめて 1 commit

video-subtitler は周回ごとに push したが、結果として `_review-notes.md` 等の closure 成果物が散逸した。**修正をまとめて 1 commit で push** する方が監査履歴が綺麗になる (Workshop 4R で v3.4 確定時に採用したパターン)。

## feedback 反映

claude-memory `feedback_audit_workflow.md`:

> CODEX 等の外部監査を反復で回す時、CODEX の指摘を待ってから1件ずつ反応するパターンに陥らない。
> 反復監査の 1 周目に、自己 ULTRATHINK で横断観点を全部洗う。
> 初回修正でこれら全部を予防的に押さえる。CODEX 監査は「答え合わせ」ではなく「最終チェック」に格下げ。

これがツールキット Fix 6 の直接的な原典。

## 関連文書

- [`docs/01-overview.md`](../docs/01-overview.md) — ランブック監査 vs コードベース監査の 2 系統分岐
- [`docs/03-five-decisive-fixes.md`](../docs/03-five-decisive-fixes.md) — Fix 6 横断 6 観点 ULTRATHINK
- [`docs/07-runbook-templates/code-audit-runbook.md`](../docs/07-runbook-templates/code-audit-runbook.md) — コードベース監査用テンプレ
- [`comparison-4r-vs-13r.md`](comparison-4r-vs-13r.md) — 3 ケース比較分析
- [`workshop-course1-snippet.md`](workshop-course1-snippet.md) — Workshop 4R (ランブック / 教材)
- [`sift-phase-c-snippet.md`](sift-phase-c-snippet.md) — SIFT 13R (ランブック / 監査)
