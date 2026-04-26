# claude-codex-audit-toolkit

> Claude Code で自分のプロジェクトを Codex CLI で監査する人のための運用ツールキット

[Claude Code](https://docs.claude.com/en/docs/claude-code) で書いたランブックや実装を、[OpenAI Codex CLI](https://github.com/openai/codex) (`codex exec` / `codex review --commit`) を使って **品質監査ループ** に乗せる際の、実証済みプロンプト設計・5 つの決定的対策・収束判定基準をまとめたツールキットです。

## なぜこれが必要か

Claude Code でランブックや教材コンテンツを書いて Codex で監査すると、ラウンドごとに finding が小出しに出続ける「**五月雨**」現象が起きやすい。Workshop Course 1 で R1=40 件 → R2=13 件 → R3=6 件 → R4=6 件停滞のように、本来 1-2 ラウンドで PASS すべきものが 4-13 ラウンド回り続ける。

原因は **Codex の問題ではなく、プロンプト設計の質**。検査軸が抽象的・重複排除を許容・過去ラウンドで反映済の修正方針を pre-condition として明示しない等で Codex が同一違和感を異なる角度から再指摘してしまう。

このツールキットは、4 つの実プロジェクト (Workshop / SIFT / RUN / CPN) で監査ループを回した経験から抽出した、安定収束させるための運用パターンを提供します。明示できる実走数値は SIFT Phase C ランブック 13 ラウンド (R13 ALL PASS) と Workshop Course 1 ランブック 4 ラウンド (R4 scope cut) の 2 ケース。

## 実証成果

| プロジェクト | ラウンド数 | 結果 | パターン |
|---|---|---|---|
| SIFT Phase C ランブック | 13 ラウンド | ALL PASS (R13) | 正常収束: 件数が単調減少 |
| Workshop Course 1 ランブック | 4 ラウンド | scope cut で確定 | 同パターン周回検出: R3-R4 で 6 件停滞 |

検証環境: Codex CLI 0.125.0 + gpt-5.5 + `model_reasoning_effort=xhigh`。実走で効いた本物のプロンプト構造は [`docs/02-anti-drip-prompt-v2.md`](docs/02-anti-drip-prompt-v2.md) 参照。なお v1 で推奨していた「重圧プロンプト」(全行 enumerate / mandatory セクション / 3 段階構造 / 全カテゴリ均等深さ) は Codex を tool ループに陥れることが判明したため廃止しました ([`docs/08-known-pitfalls.md`](docs/08-known-pitfalls.md))。

## Quick Start

### 0. 前提

- [Claude Code](https://docs.claude.com/en/docs/claude-code) がインストール済
- [OpenAI Codex CLI](https://github.com/openai/codex) がインストール済 (`npm install -g @openai/codex@latest`)
- ChatGPT 有料プラン (Plus / Pro / Business / Edu / Enterprise) で ChatGPT sign-in。Codex CLI で `gpt-5.5` が表示されない場合は `gpt-5.4` を使用 ([公式 Help](https://help.openai.com/en/articles/11369540) / [Codex Models](https://developers.openai.com/codex/models))

### 1. 監査対象は 1 ラウンド = 1 ファイルに絞る

実走で動いた構造の **最重要原則**。Codex に「全 N ファイル走査」を強制すると tool 呼び出しループに陥り、finding 出力前に session が exit します。1 ラウンドで監査対象は 1 ファイルだけ、関連参照は「必要なら Read」と明示します。

### 2. 五月雨防止 4 行ブロック + 過去ラウンド反映済リストを蓄積

R2 以降に Codex に出すプロンプトには、必ず以下のブロックを冒頭配置:

```
【五月雨防止プロンプト】 — 過去ラウンドとの矛盾 / 同一違和感の深堀り cascade を禁止。
- 過去ラウンドで反映済の修正を pre-condition として受け入れる (例: {30+ 項目蓄積})。これらを「再考すべき」として再指摘しない
- 同じ違和感の角度を変えた言い換え / 表現の揺れを別件として再指摘しない (1 違和感 = 1 件で集約)
- 1 ラウンドで全 P1/P2/P3 を重複なく列挙し、後続ラウンドでの新規発見を禁止する前提で網羅
- 矛盾する指摘は出す前に「前ラウンド方針との整合」を自己検証してから出す。それでも出すなら明示的に「前ラウンド方針 X との矛盾承知の上で」と注記
```

**最重要**: 1 行目の「(例: {30+ 項目蓄積})」に **過去ラウンドで反映済の方針を 30+ 項目蓄積して書く**。これが本物の cascade 防止仕掛けです。

詳細: [`docs/02-anti-drip-prompt-v2.md`](docs/02-anti-drip-prompt-v2.md)

### 3. 監査実行

```bash
# commit pin + placeholder 置換 (再現性担保)
TARGET_SHA=$(git rev-parse --short HEAD)
RUNBOOK_NAME="SIFT 受講者目線監査 Phase C ランブック"   # 実物のランブック名に差し替え
RUNBOOK_PATH="docs/SIFT-AUDIT-PHASE-C-MANUAL-RUNBOOK.md"  # 監査対象のパス
PREV_FINDINGS="初回"                                     # R2 以降は反映済リスト 30+ 項目

PROMPT=$(cat docs/07-runbook-templates/codex-audit-prompt.txt)
PROMPT="${PROMPT//__SHA__/$TARGET_SHA}"
PROMPT="${PROMPT//__RUNBOOK_NAME__/$RUNBOOK_NAME}"
PROMPT="${PROMPT//__RUNBOOK_PATH__/$RUNBOOK_PATH}"
PROMPT="${PROMPT//__PREV_FINDINGS__/$PREV_FINDINGS}"

# Codex exec で監査投入 (stdin は明示的にクローズ / ChatGPT sign-in が必須)
codex exec -s read-only -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  --output-last-message /tmp/codex-audit-result.md \
  "$PROMPT" < /dev/null
```

詳細: [`docs/03-five-decisive-fixes.md`](docs/03-five-decisive-fixes.md)

### 4. 収束判定

ラウンドごとの finding 件数を見て、**正常収束** か **scope creep** かを判定:

| 状態 | 機械的に判定できる条件 | 対応 |
|---|---|---|
| 正常収束 | 直近 2-3 ラウンドの総件数が下降傾向 / 矛盾指摘なし / 同一 finding の再発なし / 未解決 finding が具体行に紐づく | 継続 (上限なし) |
| scope creep | 2 ラウンド連続停滞 / 前回と矛盾する指摘 / 角度を変えた言い換え再発 | scope cut 検討 |

詳細: [`docs/04-convergence-patterns.md`](docs/04-convergence-patterns.md)

## ドキュメント

| 文書 | 内容 |
|---|---|
| [01-overview.md](docs/01-overview.md) | Claude Code + Codex 監査ループの全体像 |
| [02-anti-drip-prompt-v2.md](docs/02-anti-drip-prompt-v2.md) | 五月雨防止プロンプト v2 (実走証拠ベース 4 要素) |
| [03-five-decisive-fixes.md](docs/03-five-decisive-fixes.md) | 5 つの決定的対策 (commit pin / canonical baseline / 独立変数 / BSD sed / dotenv) |
| [04-convergence-patterns.md](docs/04-convergence-patterns.md) | 正常収束 vs scope creep の判定基準 |
| [05-env-lint-checklist.md](docs/05-env-lint-checklist.md) | 環境系 lint 14 項目 (Codex に出す前の事前チェック) |
| [06-dev-bypass-design.md](docs/06-dev-bypass-design.md) | dev/local 環境用 auth bypass の 4 原則 |
| [07-runbook-templates/](docs/07-runbook-templates/) | ランブック / プロンプトのテンプレート集 |
| [08-known-pitfalls.md](docs/08-known-pitfalls.md) | v1 重圧プロンプト廃止の実証データ |

## examples/

実プロジェクトでの適用例:

| 事例 | パターン |
|---|---|
| [workshop-course1-snippet.md](examples/workshop-course1-snippet.md) | 4 ラウンドで scope cut → v3.4 確定 |
| [sift-phase-c-snippet.md](examples/sift-phase-c-snippet.md) | 13 ラウンドで ALL PASS |
| [comparison-4r-vs-13r.md](examples/comparison-4r-vs-13r.md) | 2 つのケースの比較分析 |

## scripts/

実用シェルスクリプト:

| スクリプト | 用途 |
|---|---|
| [codex-audit-prompt-gen.sh](scripts/codex-audit-prompt-gen.sh) | プロンプト生成 (commit pin + placeholder 置換) |
| [env-lint-check.sh](scripts/env-lint-check.sh) | 環境系 lint の主要違反パターン自動検出 (docs/05 の 14 項目のうち機械検出しやすい 9 系統を grep 実装。残りは目視チェック) |

## ライセンス

[MIT License](LICENSE) — 自由に利用・改変・再配布可。出典明記推奨。

## コントリビューション

issue / PR 歓迎。実プロジェクトでの適用事例 (`examples/` への追加) は特に価値があります。

## 関連

- [Claude Code 公式ドキュメント](https://docs.claude.com/en/docs/claude-code)
- [OpenAI Codex CLI](https://github.com/openai/codex)
- [AIFCC](https://aifcc.jp) (本ツールキットの実証元コミュニティ)
