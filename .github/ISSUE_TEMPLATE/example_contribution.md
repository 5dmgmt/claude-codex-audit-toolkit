---
name: Example contribution
about: 5dmgmt 系列以外の事例追加 (特に歓迎)
title: '[Example] '
labels: example, help-wanted
---

## プロジェクト概要
- 名前 / リポ:
- 言語 / フレームワーク:
- 監査対象スコープ:

## 監査単位 (該当する系統)
- [ ] ランブック監査 (1 ラウンド = 1 ファイル)
- [ ] コードベース監査 (1 ラウンド = 1 commit / リポ全体 + AUDIT_RUNBOOK.md)

## 監査ラウンド推移 (件数比較は同一範囲 / 同一監査軸が前提)
| ラウンド / 周 | 監査対象 (ファイル名 / commit) | 旧範囲件数 | 新規範囲初回件数 | 同一軸比較可否 | 主要 finding | 適用 Fix |
|---|---|---|---|---|---|---|

> 範囲拡大 (新規ファイル追加 / 監査軸の高度化) があった場合は、旧範囲推移と新規範囲初回件数を分けて記録してください ([docs/04 §前提](../../docs/04-convergence-patterns.md) 参照)。

## 該当 / 非該当の Fix
- Fix 1 (commit pin): 該当 / 非該当 / 部分
- Fix 2 (canonical baseline): 該当 / 非該当 / 部分
- Fix 3 (独立変数 fail-fast): 該当 / 非該当 / 部分
- Fix 4 (BSD sed 互換): 該当 / 非該当 / 部分
- Fix 5 (Next.js dotenv adapter): 該当 / 非該当 / 部分
- Fix 6 (横断 6 観点 ULTRATHINK): 該当 / 非該当 / 部分

## 教訓 / 反省

## examples/ への PR
ファイル名案: `examples/<project-slug>-snippet.md`
