# コードベース監査ランブック テンプレート

> **コードベース監査用** のテンプレ。実装コード (パイプライン / アプリ全体 / 大規模 codebase) を Codex で反復監査する際に使う。
>
> **ランブック監査用** (静的文書を 1 ファイル単位で監査する場合) は [`manual-audit-runbook.md`](manual-audit-runbook.md) を使ってください。video-subtitler 5R から抽出した運用パターン。

## 使い方

1. 本ファイルを `AUDIT_RUNBOOK.md` (リポルート) または `docs/AUDIT_RUNBOOK.md` にコピー
2. 下記の placeholder を全て埋める
3. **Step 0 (ULTRATHINK 6 観点) を 1 周目に必ず実行** ([Fix 6](../03-five-decisive-fixes.md#fix-6-反復監査の-1-周目で横断-6-観点-ultrathink-を全部洗う))
4. 周回ごとに Codex 監査 → 修正 → commit → 次周

### Placeholder 一覧

| Placeholder | 意味 | 例 |
|---|---|---|
| `__PROJECT_NAME__` | プロジェクト表示名 | `video-subtitler` |
| `__REPO_PATH__` | リポ絶対パス | `$HOME/sandbox/video-subtitler` |
| `__SCOPE__` | 監査対象の scope (パイプライン / module / 全体等) | `Whisper + ffmpeg 字幕生成パイプライン全体` |
| `__INITIAL_SHA__` | 監査開始時の commit SHA | `3c4d5d7` |
| `__MODEL__` | 使用 Codex model | `gpt-5.4` (大規模コード監査では gpt-5.5 xhigh は 19 分超 hang リスクあり) |

---

# __PROJECT_NAME__ コードベース監査ランブック

- 検査対象: __SCOPE__
- リポ: __REPO_PATH__
- 開始 commit: __INITIAL_SHA__
- 使用 model: __MODEL__ xhigh

## Step 0. 横断 6 観点 ULTRATHINK (1 周目に必ず実施)

[`docs/03 Fix 6`](../03-five-decisive-fixes.md#fix-6-反復監査の-1-周目で横断-6-観点-ultrathink-を全部洗う) に従い、**1 周目に Codex を呼ぶ前に** 自己 ULTRATHINK で以下 6 観点を全部洗う。各観点で本リポにどんな具体リスクがあるかを 3-5 件ずつ書き出し、初回修正で予防的に押さえる。

### 6 観点 (本リポ固有のリスク 3-5 件ずつ列挙)

#### 1. セキュリティ
- [ ] (本リポ固有のリスク 1)
- [ ] (本リポ固有のリスク 2)
- [ ] ...

#### 2. 並行性
- [ ] (例) 並行 Phase B の output_path 衝突 = last-writer-wins
- [ ] (例) 一時ディレクトリの競合
- [ ] ...

#### 3. データフロー整合性
- [ ] (例) Whisper segment の時間軸不整合 (start > end)
- [ ] (例) SRT None 経路で字幕無効化したときの後続 step の前提
- [ ] ...

#### 4. 例外伝播
- [ ] (例) `step4_whisper_api` で Whisper 空応答時の abort
- [ ] (例) ffmpeg 失敗時の partial file 削除
- [ ] (例) 外部ライブラリ (whisper / ffmpeg-python) の例外を握りつぶさない
- [ ] ...

#### 5. リソース管理
- [ ] (例) 一時ファイル (`/tmp/foo.wav` 等) の cleanup
- [ ] (例) ffmpeg subprocess のハンドル close
- [ ] (例) 並行実行時のメモリ枯渇
- [ ] ...

#### 6. エッジケース
- [ ] (例) 空入力 (0 byte 動画 / 0 segment Whisper)
- [ ] (例) 超巨大入力 (10+ 時間動画)
- [ ] (例) 文字エンコーディング (NFD / NFC / 絵文字 / RTL)
- [ ] (例) placeholder 検出の網羅性 (`__TODO__` / `FIXME` / `XXX` / 未実装関数の `raise NotImplementedError`)
- [ ] ...

### Step 0 完了の判定

各観点 3-5 件ずつ列挙 + 初回修正で予防的に対処したことを `_ultrathink-notes.md` に記録。Codex は **「答え合わせ / 最終チェック」** に格下げ。

## Step 1. 周回ごとの Codex 監査

各周で以下を実行:

```bash
# (a) リポルートに移動
cd __REPO_PATH__

# (b) commit 状態確認 (dirty なら commit してから監査)
git status --porcelain
TARGET_SHA=$(git rev-parse HEAD)

# (c) AUDIT_RUNBOOK.md (本ファイル) を Codex に渡す
codex exec -s read-only -m __MODEL__ -c model_reasoning_effort="xhigh" \
  --skip-git-repo-check \
  --output-last-message /tmp/codex-result-N.md \
  "AUDIT_RUNBOOK.md を読み、Nth ラウンド監査。Critical/High/Medium/Low に分類。Critical/High が無ければ明示。" \
  < /dev/null

# (d) 結果を tail で確認 (出力 100KB+ になることもある)
tail -200 /tmp/codex-result-N.md
```

### Codex 監査運用上の注意

- `--skip-git-repo-check` 必須 (git 状態で Codex の挙動が変わるのを避ける)
- 大規模コード監査では `gpt-5.4 xhigh` 推奨 (`gpt-5.5 xhigh` は 19 分以上 hang する事例あり / `gpt-5.4 xhigh` は実績 4-5 分)
- 出力 138KB 超になる場合があるので tail で取得
- AUDIT_RUNBOOK.md (本ファイル) を毎周 Codex に渡すことで、ラウンド間の文脈を引き継ぐ

## Step 2. 修正反映 → commit (1 周ごとに push しない)

```bash
# 検出された Critical/High/Medium/Low を全件修正してから 1 commit
git add -A
git commit -m "fix(audit-NthRound): H{X}/M{Y}/L{Z} 反映"
```

**1 周ごとに push しない**。修正をまとめて 1 commit で push する方が `_review-notes.md` 等の closure 成果物が散逸しない。Workshop 4R / video-subtitler 5R の経験から、最後に 1 回 push が推奨。

## Step 3. 周回判定

[`../04-convergence-patterns.md`](../04-convergence-patterns.md) の判定基準で:

- **正常収束** (件数下降傾向 + 矛盾なし + 同一 finding 再発なし + 具体行紐づき): 継続
- **scope creep** (2 周連続停滞 / 注記なき矛盾 / 抽象的 finding 増加): scope cut 検討、残課題を `_review-notes.md` の「将来検討事項」に転記

## ラウンド推移記録

| 周 | model | 検出 (C/H/M/L) | 完了 commit | 主要 finding |
|---|---|---|---|---|
| 1 | __MODEL__ xhigh | C0/H?/M?/L? | __INITIAL_SHA__ | (Step 0 ULTRATHINK 6 観点で予防済の項目以外で検出) |
| 2 | __MODEL__ xhigh | | | |
| ... | | | | |

## 残存課題 (確定後の判断)

| ID | 重要度 | 違和感 | 次セッション判断 |
|---|---|---|---|
| (例) M16 | Medium | content-only fingerprint が size+mtime_ns で SHA hash ではない | portability が要るなら hash 化 |
| (例) L10 | Low | 並行 Phase B の output_path 衝突 = last-writer-wins | lock file or README 明記 |

## 関連文書

- [`../03-five-decisive-fixes.md`](../03-five-decisive-fixes.md) — 6 つの決定的対策 (Fix 6 横断観点 ULTRATHINK 含む)
- [`../04-convergence-patterns.md`](../04-convergence-patterns.md) — 収束判定基準
- [`../05-env-lint-checklist.md`](../05-env-lint-checklist.md) — 環境系 lint 14 項目
- [`manual-audit-runbook.md`](manual-audit-runbook.md) — ランブック監査用テンプレ (静的文書 1 ファイル単位)
- [`codex-audit-prompt.txt`](codex-audit-prompt.txt) — Codex 監査プロンプトテンプレート
- [`../../examples/video-subtitler-snippet.md`](../../examples/video-subtitler-snippet.md) — video-subtitler 5R 実例
