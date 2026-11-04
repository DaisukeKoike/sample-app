---
name: issue-cleanup
description: マージ済みの課題について、課題別環境・Terraformワークスペース・コンテナイメージ・ブランチを削除する。人が /issue-cleanup <番号> を実行したときだけ動く。
argument-hint: <issue番号>
disable-model-invocation: true
---

# 後片付け（人の指示でのみ実行）

引数 `$ARGUMENTS` の先頭を課題番号 `N`、残りをオプションとする。数字でなければ中止する。`--local` では以下のクラウド手順2〜4を実行しない。

## 1. マージ済みの確認（MERGED でなければ中止）
```bash
gh pr list --state all --search "N in:title" --json number,headRefName,state
```

## 2. 削除計画の提示 → 人の承認
```bash
terraform -chdir=infra/envs/issue init -input=false
terraform -chdir=infra/envs/issue workspace select issue-N
terraform -chdir=infra/envs/issue plan -destroy -input=false -out=destroy.tfplan -var="issue_id=N" -var="image_tag=cleanup"
aws ecr list-images --repository-name sample-app --region ap-northeast-1 \
  --query "imageIds[?starts_with(imageTag || '', 'issue-N-')].imageTag" --output text
```
削除されるリソース・ワークスペース名・イメージタグ・ブランチを一覧で示し、**人が「削除してよい」と答えるまで実行しない**。

## 3. 環境の削除
```bash
terraform -chdir=infra/envs/issue apply -input=false destroy.tfplan
rm -f infra/envs/issue/destroy.tfplan
terraform -chdir=infra/envs/issue workspace select default
terraform -chdir=infra/envs/issue workspace delete issue-N
```

## 4. イメージの削除
```bash
aws ecr batch-delete-image --repository-name sample-app --region ap-northeast-1 --image-ids imageTag=<タグ1> imageTag=<タグ2>
```

## 5. ブランチの削除
```bash
git switch main && git pull --ff-only
git branch -D <ブランチ名>          # Squash マージのため -d では未マージ扱いになる
git push origin --delete <ブランチ名>
```
削除した項目を一覧で報告する。途中で失敗したら以降を実行せず、残っているものを報告する。

## ローカル演習と安全確認
- `--local` ではAWS、Terraform、ECRに触れない。起動プロセスの停止は利用者に依頼する。DBを勝手に削除しない。
- 課題番号の部分一致検索だけでマージ済みと判断しない。PR本文のCloses #N、headブランチ、対象リポジトリ、MERGED状態を確認する。
- 削除承認は今回提示した対象だけに適用する。未知のリソースや他課題のデータがあれば中止する。
