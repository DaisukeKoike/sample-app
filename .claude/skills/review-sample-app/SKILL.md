---
name: review-sample-app
description: sample-app の変更差分を、共通観点と案件固有観点のチェックリストでレビューする。PR 作成前やレビュー依頼時に使う。
---

# sample-app のレビュー

対象: `git diff origin/main...HEAD`（引数で PR 番号が渡されたら `gh pr diff <番号>`）

次の観点ファイルに沿って、差分を1項目ずつ確認する:
- 共通: [checklists/common.md](checklists/common.md)
- 案件固有: [checklists/project.md](checklists/project.md)

## 出力形式
| 重要度 | 箇所 | 理由 | 修正案 |
|---|---|---|---|
| 高/中/低 | `path:line` | … | … |

- 該当なしの観点は「確認済み・指摘なし」とまとめて1行で書く
- 「高」は取り込み前に必須で直す。課題範囲外の指摘は「別課題候補」として分ける（自分では直さない）
- 最後に「観点ファイルに追加すべき新しい観点」があれば提案する
