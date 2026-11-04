---
name: pr-create
description: 現在の作業ブランチから変更依頼（Pull Request）を作成する。差分のファイル名で完了済みを含む全課題を検索し、中身を読んで関連を判断したうえで、型に沿った本文と Closes #番号 を入れる。
---

# 変更依頼の作成

## 0. 前提確認（満たさなければ中止）
- 現在ブランチが `main` ではない。名前から課題番号 `N` を取り出せる
- `git status` がクリーン（未コミットがあれば人に確認）
- CLAUDE.md のテスト手順が成功している

## 1. 差分の把握
```bash
git fetch origin main
git diff --name-only origin/main...HEAD
git diff --stat origin/main...HEAD
gh issue view N --json title,body
```

## 2. 関連課題の抽出（検索結果を貼るだけにしない）
変更ファイルごとに、ファイル名（拡張子なし）と主要な関数名で検索する:
```bash
gh issue list --state all --limit 30 --search "<ファイル名や関数名> in:title,body"
```
候補は `gh issue view <番号> --json title,body` で**1件ずつ読み**、`原因` / `同じ関数を変更` / `確認したが影響なし` / 無関係（載せない）に分類する。

## 3. 本文の作成（`.github/pull_request_template.md` の型で `pr-body.md` に書く）
- 「Related issues」には `Closes #N` と、分類結果を1行ずつ
- 「Test results」には実行コマンドと件数
- 「Review points」には人に特に見てほしい点
- 「担当者の説明」欄は **空欄のまま**（担当者が自分の言葉で書く）

## 4. 作成
```bash
git push -u origin HEAD
gh pr create --base main --title "<種別>: <要約> (#N)" --body-file pr-body.md
rm -f pr-body.md
```
PR の URL を示し、「担当者の説明」欄の記入を人に依頼して終了する。マージは行わない。

## ACトレーサビリティと証拠
- Issueの全ACを読み、AC / 変更箇所 / テスト名 / 実行コマンド / 結果 の表を本文に追加する。
- 未実行は未実行と書く。画面確認をAPIテストで代用したとは言わない。
- 既知の演習不具合の xfail と新規の失敗を区別する。修正対象の xfail を解除し、通常テストへ昇格する。
- TRAINING_BUGS=off にして合格させるだけの修正は禁止。
- 互換性、DB変更、切戻し、未解決事項を記載する。
- 同じheadの既存PRがあれば重複作成せず内容を確認して更新する。
- 必須AC未達・未解決の高重要度指摘がある場合は通常PR作成を停止し、必要なら人の指示でDraftにする。

## 設計図
- 状態遷移・処理順・DB構造・分岐を変えた場合は、変更後の mermaid 図を本文「設計図」に入れ、Issueの図との差分を1行で説明する（`.claude/uml-guide.md`）。変えていなければ「図: 変更なし」。
- `python tools/check-mermaid.py pr-body.md` を実行する。
