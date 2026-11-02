---
name: issue-start
description: 課題番号を受け取り、命名規則どおりのブランチと課題専用の検証環境（ECS/ALB/Route53）を構築し、確認用URLを返す。/issue-start <番号> で使う。修正後の環境更新にも使う。
argument-hint: <issue番号>
---

# 着手（ブランチと課題別環境の構築）

引数 `$ARGUMENTS` を課題番号 `N` とする。数字でなければ中止する。
コマンドは bash で実行する。`terraform` が見つからなければ先に `export PATH="$HOME/.ai-harness/bin:$PATH"`。

## 1. 課題の取得
```bash
gh issue view N --json number,title,body,labels,state
```
- state が OPEN でなければ中止。
- ラベルから種別: bug→`fix` / enhancement→`feat` / それ以外→`chore`
- タイトルから英小文字・ハイフンの要約（3語以内）→ ブランチ名 `<種別>/N-<要約>`

## 2. ブランチ作成（既にあれば切り替えのみ）
```bash
git switch main && git pull --ff-only
git switch -c <ブランチ名>      # 既存なら: git switch <ブランチ名>
```

## 3. イメージの作成と登録（docker が起動していなければ中止して人に伝える）
```bash
SHA=$(git rev-parse --short HEAD)
REG=000000000000.dkr.ecr.ap-northeast-1.amazonaws.com
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $REG
docker build -f Dockerfile -t $REG/sample-app:issue-N-$SHA .
docker push $REG/sample-app:issue-N-$SHA
```

## 4. 課題別ワークスペースで構築（計画を保存してから適用）
```bash
terraform -chdir=infra/envs/issue init -input=false
terraform -chdir=infra/envs/issue workspace select -or-create issue-N
terraform -chdir=infra/envs/issue plan -input=false -out=tfplan -var="issue_id=N" -var="image_tag=issue-N-$SHA"
terraform -chdir=infra/envs/issue apply -input=false tfplan
rm -f infra/envs/issue/tfplan
```
- plan に削除（destroy）が含まれる、または 5種類（タスク定義・サービス・ターゲットグループ・リスナールール・Route53レコード）以外を作る場合は **apply せず中止して人に報告**。
- `tools/issue-env-audit.sh` が上限超過を返したら中止し、結果を示す。

## 5. URL の提示
```bash
terraform -chdir=infra/envs/issue output -raw app_url
```
URL・ブランチ名・イメージタグを報告する。安定まで1〜2分かかる旨を添える。

## 修正後の環境更新
コミット後に手順3〜5を再実行する（新しい SHA のタグで plan → apply）。
