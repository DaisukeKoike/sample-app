# CLAUDE.md — sample-app

このファイルは Claude Code（VS Code 拡張 / CLI）が毎回読み込む前提です。ここに書いたことは「お願い」ではなく、
Hooks・CI・ルールセットで機械的にも担保されています。ミスや指摘が出たら、ここ・スキル・Hooks・テストのいずれかに反映してください。

## 開発フロー（必ずこの順序）
1. 起票: `/issue-create` — 過去課題（完了済み含む）を検索してから、型に沿って起票
2. 着手: `/issue-start <番号>` — ブランチ作成と課題別環境の構築
3. 実装・テスト・AIレビュー（`/review-sample-app`）
4. 変更依頼: `/pr-create` — 関連課題を洗い出して PR を作成
5. 取り込み: **人が** 承認し Squash and Merge（AI は `gh pr merge` を実行しない）
6. 後片付け: **人の指示で** `/issue-cleanup <番号>`

## 守ること
- 1課題1ブランチ1PR。実装中に見つけた別の不具合は直さず、`/issue-create` で別課題として起票する
- `main` へ直接 push しない。force push しない
- Terraform の apply は `infra/envs/issue` の `issue-<番号>` ワークスペースでのみ行う。`infra/base`・`infra/bootstrap` は人が操作する
- `.env`・秘密鍵・認証情報は読まない、出力しない、コミットしない
- ログに個人情報を出さない

## 実行環境
- コマンドは bash で実行する（Windows は Git Bash）。PowerShell 構文を使わない
- AWS は `AWS_PROFILE=sample-app-ai`（権限を絞った AI 用ロール）で操作する。プロファイルを切り替えない
- terraform / jq は `~/.ai-harness/bin` にある。見つからない場合は `export PATH="$HOME/.ai-harness/bin:$PATH"` を先に実行する

## ブランチ命名規則
`<種別>/<課題番号>-<英小文字の要約>`（例: `fix/128-date-filter`）
種別: `fix`（bug）/ `feat`（enhancement）/ `chore`（その他）

## コーディング規約
- Python: ruff（format / lint）準拠、型ヒント必須、例外は握りつぶさない
- Angular / TypeScript: eslint・prettier 準拠
- 日付・時刻は日本時間（Asia/Tokyo）で扱い、期間の終了日は当日を含む
- 既存コードの書き方に合わせる。新しいライブラリの追加は PR 本文で理由を説明する

## テスト手順（毎回同じ手順で実行）
```bash
# API (Python)
cd api && python -m pytest -q
# 画面 (Angular)
cd  && npx ng test --watch=false --browsers=ChromeHeadless
# インフラ変更がある場合
terraform -chdir=infra/envs/issue fmt -check && terraform -chdir=infra/envs/issue validate
```
- 該当ディレクトリが無い手順は飛ばす
- 完了条件は Issue に書かれた「完了条件」をテストで確かめること
- 修正後は課題別環境を更新し（`/issue-start` の手順3〜5を再実行）、専用URLで確認する

## 課題別環境
- URL: `https://issue-<番号>.dev.example.com`
- 作るのは ECS タスク定義・サービス・ターゲットグループ・リスナールール・Route53 レコードの5つだけ
- 同時稼働は最大 20 環境（`tools/issue-env-audit.sh` で確認）
