# v0.4-beta / v0.5-nextjs-supabase 凍結時の未反映 finding (R5-R6 時点)

> 2026-04-28 / R5 自己監査 P1×12 のうち構造バグ・実用ガード **7 件反映 + 残 5 件凍結** → R6 で凍結方針の機能を確認、R6 P1×8 全件反映 → v0.5-nextjs-supabase 特化方針へ遷移。下記 5 件 (R5 凍結) は v0.5 でも判断不変 (state-of-time 系の docs 転記 / 修正の負債化パターン / Next.js + Supabase 特化でも内容は変わらない) で **凍結継続**。v1.0 で外部事例の知見を踏まえて再判定するのは下記 5 件のみ。

## R6 観察結果 (凍結方針の妥当性確認)

| ラウンド | P1 | P2 | P3 | 合計 | 旧 10 |
|---|---|---|---|---|---|
| R5 | 12 | 56 | 31 | 99 | 51 |
| **R6** | **8** | **37** | **14** | **59** | **33** |

- 旧 10 ファイル **R5=51 → R6=33 (-35%)** で同一範囲下降傾向継続
- **ALL PASS 2 件** (`docs/07-runbook-templates/codex-audit-prompt.txt` / `examples/workshop-course1-snippet.md`) = 真の収束兆候
- **凍結項目への再指摘ゼロ** = 五月雨防止 + 凍結宣言が機能している
- R6 P1×8 はすべて R5 反映の波及漏れ・構造的精緻化要求 (例: docs/04 比較単位を「同一監査単位」に拡張 / docs/06 境界別契約 / scripts #10b printf stdout 漏洩検出 等) で **全件反映**
- R7 は回さない (外部事例で軸が変わってから回す。自己内ループで更に細部を見ても汎化価値は増えない)

## 凍結理由 (なぜ反映しないか)

R3-R5 の自己監査で観察された **修正の負債化** パターン:

- 「R4 反映 commit を README/CONTRIBUTING/self-audit history の表に転記しろ」が R5 で大量発生
- これを反映すると R6 で「R5 反映 commit を表に転記しろ」が必ず出る = **永久機関**
- `docs/04-convergence-patterns.md` で警告している「説明追加要求系 / 修正の負債化」の典型
- ファイル別では `examples/workshop-course1-snippet.md` (3→3→4→5→4) も同型の微増パターンを示す

外部事例 (5dmgmt 系列以外) が入って軸が変わるまで、これらは反映せずに凍結する。

## 凍結項目一覧 (5 件)

### 1. README Self-audit history table の R4-R5 行追加 (R5 readme P1×1)

- 指摘: 「対象 commit は 70ea5ca の R4 P1×16 反映後ですが、README の表は R3 で止まり、行58も R3 時点の『scope creep 予兆として要観察』のまま」
- なぜ凍結: R5 でも同型指摘が出る (R5 の状態を表に転記しろ → R6 で R5 反映 commit を転記しろ → 永久ループ)
- 代替対応: R5 表記の **要点 1 行 + 凍結宣言** に圧縮済 (`README.md` §Self-audit history)。詳細表は [`examples/self-audit-history.md`](../examples/self-audit-history.md) に集約

### 2. CONTRIBUTING の「現状 P1 残あり」表記更新 (R5 contributing P1×1)

- 指摘: 「70ea5ca は R4 P1×16 解消コミットですが、CONTRIBUTING では『現状 P1 残あり』のまま」
- なぜ凍結: 1 と同型 (state-of-time の docs 転記)
- 代替対応: 「v0.4-beta 凍結」明示に書き換え済 (`CONTRIBUTING.md` §現在の version と成熟度)

### 3. examples/self-audit-history.md の R4 行追加 (R5 exselfaudit P1×1)

- 指摘: 「70ea5ca は R4 反映 commit ですが、対象ファイルは R1-R3 記録のまま」
- なぜ凍結: 1, 2 と同型
- 代替対応: R4-R5 行追加 + 旧 10 ファイル列追加 + 波紋解消注記まで反映済 (R5 反映で本ファイルに到達できる前提を作った上で凍結)

### 4. examples/self-audit-history.md の scope creep 予兆ラベル R4 反映 (R5 exselfaudit P1×1)

- 指摘: 「§R3 で観察された scope creep 予兆 が `次 R4 で観察` のままで、R4 後の確定判定が反映されていない」
- なぜ凍結: 1-3 と同型
- 代替対応: §R4 で確定した scope creep 予兆判定 に書き換え + ファイル別 R3-R5 結果を表で確定済

### 5. examples/video-subtitler-snippet.md の `tail で取得` 表現言い換え (R5 exvideosub P1×1)

- 指摘: 「100 KB+ も発生 (tail で取得) は、R4 後の docs/07/code 方針『出力ファイルが正本 / tail は quick view』と矛盾」
- なぜ凍結: docs/07/code 本体は既に R4 で正しく書かれており、video-subtitler の事例記述は **2026-03 当時の運用記録 (历史的事実)** として読める。事例として「当時はこうだった」を保つことに価値がある
- 代替対応: docs/07/code-audit-runbook.md 行105-107 に「正本は出力ファイル / rg で全件抽出 / tail は quick view」が明記済。事例側の言い換えは不要

### 6. docs/07/runbook-templates/manual-audit-runbook.md の Fix 1 完全手順転記 (R5 docs07manual P1×1)

- 指摘: 「Codex 監査ステップが Fix 1 の完全手順 (dirty fail-fast + cat-file -e) になっていない」
- なぜ凍結: docs/03 Fix 1 と README Quick Start に **完全手順が既に存在**。docs/07/manual のテンプレ側は「README Quick Start / docs/03 Fix 1 を参照」で十分 (転記すると 3 箇所同期メンテになる)
- 代替対応: docs/07/manual 冒頭で「Fix 1 完全手順は docs/03 を参照」と明示する手はあるが、これは v1.0 で全 docs を見直すときに統合判断する

## v1.0 で再判定するタイミング

外部事例 (5dmgmt 系列以外の Rails / Django / Go / Python pipeline 等) が入って:

- コア / adapter 階層の境界が変わる
- 軸数 (今は 5-7) や Fix の数 (今は 6) が変わる
- N=1 仮説の汎化主張が弱まる / 強まる

このどれかが起きたら、本ファイルの 6 項目を再判定する。**外部事例なしに自己内ループで再判定しない** (これが凍結の核心)。

## 関連文書

- [`../README.md`](../README.md) §Self-audit history — 凍結宣言
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) §現在の version と成熟度 — v1.0 到達条件
- [`../examples/self-audit-history.md`](../examples/self-audit-history.md) — R1-R5 件数推移詳細
- [`04-convergence-patterns.md`](04-convergence-patterns.md) — scope creep / 修正の負債化判定基準
