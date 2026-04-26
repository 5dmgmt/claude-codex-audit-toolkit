# claude-codex-audit-toolkit

> Claude Code で自分のプロジェクトを Codex CLI で監査する人のための運用ツールキット

[Claude Code](https://docs.claude.com/en/docs/claude-code) で書いたランブックや実装を、[OpenAI Codex CLI](https://github.com/openai/codex) (`codex exec` / `codex review --commit`) を使って **品質監査ループ** に乗せる際の、実証済みプロンプト設計・5 つの決定的対策・収束判定基準をまとめたツールキットです。

## なぜこれが必要か

Claude Code でランブックや教材コンテンツを書いて Codex で監査すると、ラウンドごとに finding が小出しに出続ける「**五月雨**」現象が起きやすい。1 ラウンドで 40 件 → 2 ラウンドで 13 件 → 3 ラウンドで 6 件 → 4 ラウンドで 6 件停滞、のように本来 1-2 ラウンドで PASS すべきものが 5-13 ラウンド回り続ける。

原因は **Codex の問題ではなく、プロンプト設計の質**。検査軸が抽象的・重複排除を許容・全行 enumerate 強制が弱い等で Codex が無意識に重複排除する。

このツールキットは、4 つの実プロジェクト (Workshop / SIFT / RUN / CPN) で **計 30+ ラウンド** 監査を回した経験から抽出した、安定収束させるための運用パターンを提供します。

## 実証成果

| プロジェクト | ラウンド数 | 結果 | パターン |
|---|---|---|---|
| SIFT Phase C ランブック | 13 ラウンド | ALL PASS (R13) | 正常収束: P2×13 → P2×5 → P2×2 → ALL PASS |
| Workshop Course 1 ランブック | 4 ラウンド | scope cut で確定 | 同パターン周回検出: 6 件停滞で v3.4 確定 |

## Quick Start

### 0. 前提

- [Claude Code](https://docs.claude.com/en/docs/claude-code) がインストール済
- [OpenAI Codex CLI](https://github.com/openai/codex) がインストール済 (`npm install -g @openai/codex@latest`)
- ChatGPT Plus / Team / Enterprise アカウント (`gpt-5.5` 利用に必要)

### 1. 五月雨防止プロンプト v2 を冒頭に置く

R2 以降に Codex に出すプロンプトには、必ず以下のブロックを冒頭配置:

```
【五月雨防止プロンプト】 — 過去ラウンドとの矛盾 / 同一違和感の深堀り cascade を禁止。
- 過去ラウンドで反映済の修正を pre-condition として受け入れる。これらを「再考すべき」として再指摘しない
- 同じ違和感の角度を変えた言い換え / 表現の揺れを別件として再指摘しない (1 違和感 = 1 件で集約)
- 1 ラウンドで全 P1/P2/P3 を重複なく列挙し、後続ラウンドでの新規発見を禁止する前提で網羅
- 矛盾する指摘は出す前に「前ラウンド方針との整合」を自己検証してから出す。それでも出すなら明示的に「前ラウンド方針 X との矛盾承知の上で」と注記
```

詳細: [`docs/02-anti-drip-prompt-v2.md`](docs/02-anti-drip-prompt-v2.md)

### 2. 監査実行

```bash
# commit pin + placeholder 置換 (再現性担保)
TARGET_SHA=$(git rev-parse --short HEAD)
PROMPT=$(cat docs/07-runbook-templates/codex-audit-prompt.txt)
PROMPT="${PROMPT//__SHA__/$TARGET_SHA}"

# Codex exec で監査投入
codex exec -s read-only -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  "$PROMPT" < /dev/null
```

詳細: [`docs/03-five-decisive-fixes.md`](docs/03-five-decisive-fixes.md)

### 3. 収束判定

ラウンドごとの finding 件数を見て、**正常収束** か **scope creep** かを判定:

| 状態 | パターン | 対応 |
|---|---|---|
| 正常収束 | 件数が単調減少 / 矛盾指摘なし / 粒度が細かくなる | 継続 (上限なし) |
| scope creep | 同じ指摘が周回 / 件数停滞 / 前回と矛盾する指摘 | scope cut 検討 |

詳細: [`docs/04-convergence-patterns.md`](docs/04-convergence-patterns.md)

## ドキュメント

| 文書 | 内容 |
|---|---|
| [01-overview.md](docs/01-overview.md) | Claude Code + Codex 監査ループの全体像 |
| [02-anti-drip-prompt-v2.md](docs/02-anti-drip-prompt-v2.md) | 五月雨防止プロンプト v2 (7 要素テンプレ) |
| [03-five-decisive-fixes.md](docs/03-five-decisive-fixes.md) | 5 つの決定的対策 (commit pin / canonical baseline / 独立変数 / BSD sed / dotenv) |
| [04-convergence-patterns.md](docs/04-convergence-patterns.md) | 正常収束 vs scope creep の判定基準 |
| [05-env-lint-checklist.md](docs/05-env-lint-checklist.md) | 環境系 lint 14 項目 (Codex に出す前の事前チェック) |
| [06-dev-bypass-design.md](docs/06-dev-bypass-design.md) | dev/local 環境用 auth bypass の 4 原則 |
| [07-runbook-templates/](docs/07-runbook-templates/) | ランブック / プロンプトのテンプレート集 |

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
| [env-lint-check.sh](scripts/env-lint-check.sh) | 環境系 lint 14 項目の自動実行 |

## ライセンス

[MIT License](LICENSE) — 自由に利用・改変・再配布可。出典明記推奨。

## コントリビューション

issue / PR 歓迎。実プロジェクトでの適用事例 (`examples/` への追加) は特に価値があります。

## 関連

- [Claude Code 公式ドキュメント](https://docs.claude.com/en/docs/claude-code)
- [OpenAI Codex CLI](https://github.com/openai/codex)
- [AIFCC](https://aifcc.jp) (本ツールキットの実証元コミュニティ)
