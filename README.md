# claude-codex-audit-toolkit

> Claude Code で自分のプロジェクトを Codex CLI で監査する人のための運用ツールキット
>
> **Version**: v0.4-beta — 5dmgmt 内部で 3 ケース実証済 / 5dmgmt 系列以外の事例を募集中 ([CONTRIBUTING.md](CONTRIBUTING.md))

[Claude Code](https://docs.claude.com/en/docs/claude-code) で書いたランブックや実装を、[OpenAI Codex CLI](https://github.com/openai/codex) (`codex exec` / `codex review --commit`) を使って **品質監査ループ** に乗せる際の、実証済みプロンプト設計・6 つの決定的対策・収束判定基準をまとめたツールキットです。

## なぜこれが必要か

Claude Code でランブックや実装を Codex で監査すると、ラウンドごとに finding が小出しに出続ける「**五月雨**」現象が起きやすい。**短いラウンドで PASS または妥当な scope cut の確定に到達しやすくする** ことが本ツールキットのねらい (具体的なラウンド数は対象により大きく異なる)。

主因は **プロンプト設計・ランブック構造・監査基盤の決定性不足** にあり、Codex 本体の良否ではない。検査軸が抽象的・重複排除を許容・過去ラウンドで反映済の修正方針を pre-condition として明示しない等で Codex が同一違和感を異なる角度から再指摘してしまう。

## 適用範囲 (どこまで効くか / docs/05 §適用範囲表を正本)

| 範囲 | 階層 | カバー |
|---|---|---|
| 五月雨防止プロンプト v2 (4 行ブロック + 蓄積リスト) / Fix 1, 3, 4 / 収束判定 / docs/05 #1/#2/#3/#4/#6/#10/#11/#13/#14 | **コア (フレームワーク中立)** | 全プロジェクト |
| Fix 6 (横断 6 観点 ULTRATHINK) | **コア (中立)** | コードベース監査全般で必須 / ランブック監査でも該当観点 (データフロー整合性 / 例外伝播 / エッジケース等) は適用可 |
| docs/05 #12 (codex `-s read-only`) | **コア (Codex CLI 固有)** | 本ツールキット利用者全員 |
| Fix 2 (DOM canonical baseline) | Adapter (Web UI 検証) | Web UI / DOM 検証を含むプロジェクト |
| Fix 5 (dotenv 4 load slot + 6 表記) | Adapter (Next.js dotenv) | Next.js プロジェクト |
| docs/05 #5 (npm run dev port pin) | Adapter (Node.js 系) | Node.js / npm 系プロジェクト |
| docs/05 #7/#8/#9 (next-env.d.ts / dotenv ファイル / .env.local) | Adapter (Next.js 固有) | Next.js プロジェクト |
| docs/06 (dev bypass 4 原則) | **Adapter: Next.js + 自前 auth** | Next.js + 自前 auth (NextAuth / Supabase Auth / Auth0 等は別 adapter 必要) |
| Rails / Django / Go / NextAuth / Supabase Auth / 他 framework | **未整備 (Adapter 募集中)** | community contribution 待ち ([CONTRIBUTING.md](CONTRIBUTING.md)) |

## 実証成果

| プロジェクト | 系統 | ラウンド数 | 結果 | パターン |
|---|---|---|---|---|
| SIFT Phase C ランブック | ランブック (受講者ジャーニー監査) | 13 ラウンド | ALL PASS (R13) | 正常収束: 全体トレンドが下降 |
| Workshop Course 1 ランブック | ランブック (教材) | 4 ラウンド | scope cut で確定 | 同パターン周回検出: R3-R4 で 6 件停滞 |
| video-subtitler | コードベース (Whisper+ffmpeg pipeline) | 5 周 | 下降収束 (残 M16+L10 は次セッション判断) | Fix 6 不在で五月雨式 → 横断観点 ULTRATHINK が必須と判明 |

検証環境: Codex CLI 0.125.0。**モデル選択は N=各 1-2 ケースから抽出した仮説**:
- ランブック監査 → `gpt-5.5 xhigh` (SIFT 13R / Workshop 4R で完走実績)
- コードベース監査 → `gpt-5.4 xhigh` (video-subtitler 5R で確定 / `gpt-5.5 xhigh` は 19 分超の hang 1 例あり、根本原因未特定)

他フレームワーク / 他コードベースでの汎化は要検証。`gpt-5.4 xhigh` は **video-subtitler 5R で完走実績** (確定ではなく観察値)。実走で効いた本物のプロンプト構造は [`docs/02-anti-drip-prompt-v2.md`](docs/02-anti-drip-prompt-v2.md) 参照。なお v1 で推奨していた「重圧プロンプト」(全行 enumerate / mandatory セクション / 3 段階構造 / 全カテゴリ均等深さ) は Codex を tool ループに陥れることが判明したため廃止しました ([`docs/08-known-pitfalls.md`](docs/08-known-pitfalls.md))。

## Self-audit history (本リポ自身を本ツールキットで監査した記録)

詳細な件数推移とファイル別追跡は [`examples/self-audit-history.md`](examples/self-audit-history.md) 参照。要点のみ:

- **R1-R5 を回した結果** (R3 から範囲拡大 18-19 ファイル): 旧 10 ファイル合計が R1=62 → R2=58 → R3=48 → R4=56 → R5=51 で **-18% 下降傾向維持** (R4 の +17% は 12e7e95 自己検証反映の波紋で、R5 で再下降して波紋解消確定)
- **scope creep 予兆ファイル**: docs/07/manual (5→7→9→6→5) は減衰確定 ✅ / ex/workshop-course1 (3→3→4→5→4) は継続監視 ⚠
- R5 残 P1 のうち**構造バグ・実用ガード 7 件は反映**、**説明追加要求系 5 件は反映せず凍結** (`docs/_review-notes-v0.4-beta-frozen.md` に転記、v1.0 で外部事例の知見を踏まえて再考)

> **v0.4-beta 凍結 (2026-04-28)**: 自己監査ループは R5 で凍結します。理由は (a) 旧 10 ファイル件数の同一範囲下降傾向は確認済 / (b) 残 P1 の大半が「R5 時点の状態を docs に転記しろ」型の説明追加要求 = `docs/04` で警告している **修正の負債化** パターンで、ループを延ばすほど発生する自家中毒構造 / (c) 5dmgmt 系列以外の事例なしに自己内ループだけで refine しても汎化価値が増えない。R6 は **5dmgmt 系列以外の事例 (CONTRIBUTING.md 参照) が入って軸が変わってから** 回します。

## Quick Start

### 0. 前提

- [Claude Code](https://docs.claude.com/en/docs/claude-code) がインストール済
- [OpenAI Codex CLI](https://github.com/openai/codex) がインストール済 (`npm install -g @openai/codex@latest`)
- ChatGPT 有料プラン (Plus / Pro / Business / Edu / Enterprise) で ChatGPT sign-in。Codex CLI で `gpt-5.5` が表示されない場合は `gpt-5.4` を使用 ([公式 Help](https://help.openai.com/en/articles/11369540) / [Codex Models](https://developers.openai.com/codex/models))

### 1. 監査対象を系統に応じて絞る

**ランブック監査** (静的文書): 1 ラウンド = **1 ファイル**。Codex に「全 N ファイル走査」を強制すると tool 呼び出しループに陥り、finding 出力前に session が exit します。

**コードベース監査** (実装コード / pipeline): 1 ラウンド = **1 commit (リポ全体 / 複数ファイル)**。`AUDIT_RUNBOOK.md` を repo に置いて毎周 Codex に渡す + `--skip-git-repo-check` 必須。詳細は [`docs/07-runbook-templates/code-audit-runbook.md`](docs/07-runbook-templates/code-audit-runbook.md) 参照。

どちらも関連参照は「必要なら Read」と明示します。

### 2. 五月雨防止 4 行ブロック + 過去ラウンド反映済リストを蓄積

R2 以降に Codex に出すプロンプトには、必ず以下のブロックを冒頭配置:

```
【五月雨防止プロンプト】 — 過去ラウンドとの矛盾 / 同一違和感の深堀り cascade を禁止。
- 過去ラウンドで反映済の修正を pre-condition として受け入れる (例: {30+ 項目蓄積})。これらを「再考すべき」として再指摘しない
- 同じ違和感の角度を変えた言い換え / 表現の揺れを別件として再指摘しない (1 違和感 = 1 件で集約)
- 1 ラウンドで全 P1/P2/P3 を重複なく列挙し、後続ラウンドでの新規発見を禁止する前提で網羅
- 矛盾する指摘は出す前に「前ラウンド方針との整合」を自己検証してから出す。それでも出すなら明示的に「前ラウンド方針 X との矛盾承知の上で」と注記
```

**最重要**: 1 つ目の箇条書きの「(例: {30+ 項目蓄積})」に **過去ラウンドで反映済の方針を 30+ 項目蓄積して書く**。これが本物の cascade 防止仕掛けです。

詳細: [`docs/02-anti-drip-prompt-v2.md`](docs/02-anti-drip-prompt-v2.md)

### 3. 監査実行 (docs/03 Fix 1 完全手順 + scripts/codex-audit-prompt-gen.sh 推奨)

```bash
# (a) 変更を commit してから監査 (未コミット修正があると古い SHA を監査するリスク)
git add -A && git commit -m "..."

# (b) full SHA 取得 (--short は監査証跡として弱い)
TARGET_SHA=$(git rev-parse HEAD)

# (c) dirty tree fail-fast
STATUS_OUT=$(git status --porcelain=v1 --untracked-files=all 2>&1)
[ -z "$STATUS_OUT" ] || { echo "FAIL: dirty tree"; echo "$STATUS_OUT"; exit 1; }

# (d) snapshot 内に対象ファイルが存在することを確認
RUNBOOK_PATH="docs/SIFT-AUDIT-PHASE-C-MANUAL-RUNBOOK.md"  # 監査対象のパス
git cat-file -e "$TARGET_SHA:$RUNBOOK_PATH" \
  || { echo "FAIL: $RUNBOOK_PATH not in $TARGET_SHA"; exit 1; }

# (e) generator 経由で prompt 生成 (内部で sed '/^##/d' + 4 placeholder 置換 + 必須変数 fail-fast)
./scripts/codex-audit-prompt-gen.sh \
  --runbook "$RUNBOOK_PATH" \
  --runbook-name "SIFT 受講者目線監査 Phase C ランブック" \
  --prev-findings "初回" \
  > /tmp/codex-prompt.txt

# (f) generator 出力に残る `{本ランブック固有...}` の手動具体化 (必須)
#     テンプレ docs/07-runbook-templates/codex-audit-prompt.txt の監査軸 4 / 関連参照ファイル
#     には `{本ランブック固有の整合軸}` 等の placeholder が残るので、エディタで開いて
#     対象ランブックに合わせた具体内容に書き換える (or 該当行を削除)。
#     (g) の preflight が `\{[^}]*\}` を必ず検出するので、書き換え忘れは止まる。
$EDITOR /tmp/codex-prompt.txt

# (g) 未解決 placeholder の preflight (本ランブック固有編集の埋め忘れ検出)
grep -nE '\{[^}]*\}|__[A-Z_]+__' /tmp/codex-prompt.txt \
  && { echo "FAIL: prompt に未解決 placeholder が残っている"; exit 1; } || true

# (h) Codex exec で監査投入 (stdin 明示クローズ / ランブック監査=gpt-5.5 / コード監査=gpt-5.4 + --skip-git-repo-check)
codex exec -s read-only -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  --output-last-message /tmp/codex-audit-result.md \
  "$(cat /tmp/codex-prompt.txt)" < /dev/null
```

詳細: [`docs/03-five-decisive-fixes.md`](docs/03-five-decisive-fixes.md) (Fix 1 commit pin + dirty check + snapshot 確認の完全手順)

### 4. 収束判定

ラウンドごとの finding 件数を見て、**正常収束** か **scope creep** かを判定:

| 状態 | 機械的に判定できる条件 | 対応 |
|---|---|---|
| 正常収束 | 直近 2-3 ラウンドで **同一ファイル / 同一監査軸換算** の件数が下降傾向 / 矛盾指摘なし / 同一 finding の再発なし / 未解決 finding が具体行に紐づく | 継続 (上限なし) |
| scope creep | 同一範囲で 2 ラウンド連続停滞 / 前回と矛盾する指摘 / 角度を変えた言い換え再発 / 抽象的 finding 増加 | scope cut 検討 |

> 範囲拡大時 (新規ファイル追加 / 監査軸の高度化) は **総件数だけで判断しない**。旧範囲の推移と新規範囲の初回件数を分けて評価。詳細: [`docs/04-convergence-patterns.md`](docs/04-convergence-patterns.md) §前提 + [`examples/self-audit-history.md`](examples/self-audit-history.md)

詳細: [`docs/04-convergence-patterns.md`](docs/04-convergence-patterns.md)

## ドキュメント

| 文書 | 内容 |
|---|---|
| [01-overview.md](docs/01-overview.md) | Claude Code + Codex 監査ループの全体像 |
| [02-anti-drip-prompt-v2.md](docs/02-anti-drip-prompt-v2.md) | 五月雨防止プロンプト v2 (実走証拠ベース 4 要素) |
| [03-five-decisive-fixes.md](docs/03-five-decisive-fixes.md) | 6 つの決定的対策 (commit pin / canonical baseline / 独立変数 / BSD sed / dotenv / **横断 6 観点 ULTRATHINK**) |
| [04-convergence-patterns.md](docs/04-convergence-patterns.md) | 正常収束 vs scope creep の判定基準 |
| [05-env-lint-checklist.md](docs/05-env-lint-checklist.md) | 環境系 lint 14 項目 (Codex に出す前の事前チェック) |
| [06-dev-bypass-design.md](docs/06-dev-bypass-design.md) | dev/local 環境用 auth bypass の 4 原則 |
| [07-runbook-templates/](docs/07-runbook-templates/) | ランブック / プロンプトのテンプレート集 |
| [08-known-pitfalls.md](docs/08-known-pitfalls.md) | v1 重圧プロンプト廃止の実証データ |

## examples/

実プロジェクトでの適用例:

| 事例 | パターン |
|---|---|
| [workshop-course1-snippet.md](examples/workshop-course1-snippet.md) | Workshop 4R で scope cut → v3.4 確定 (ランブック / 教材) |
| [sift-phase-c-snippet.md](examples/sift-phase-c-snippet.md) | SIFT 13R で ALL PASS (ランブック / 受講者ジャーニー監査) |
| [video-subtitler-snippet.md](examples/video-subtitler-snippet.md) | video-subtitler 5R で下降収束 (コードベース / Whisper+ffmpeg pipeline) |
| [comparison-4r-vs-13r.md](examples/comparison-4r-vs-13r.md) | 3 ケースの比較分析 (ファイル名は維持) |

## scripts/

実用シェルスクリプト:

| スクリプト | 用途 |
|---|---|
| [codex-audit-prompt-gen.sh](scripts/codex-audit-prompt-gen.sh) | プロンプト生成 (commit pin + 4 placeholder 置換 + `##` コメント除去) |
| [env-lint-check.sh](scripts/env-lint-check.sh) | 環境系 lint の主要違反パターン自動検出 (docs/05 の 14 項目のうち機械検出しやすい 10 系統を grep 実装。残り 4 項目は目視チェック) |

## ライセンス

[MIT License](LICENSE) — 自由に利用・改変・再配布可。出典明記推奨。

## コントリビューション

issue / PR 歓迎。実プロジェクトでの適用事例 (`examples/` への追加) は特に価値があります。

## 関連

- [Claude Code 公式ドキュメント](https://docs.claude.com/en/docs/claude-code)
- [OpenAI Codex CLI](https://github.com/openai/codex)
- [AIFCC](https://aifcc.jp) (本ツールキットの実証元コミュニティ)
