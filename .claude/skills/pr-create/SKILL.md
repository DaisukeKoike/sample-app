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
