# =============================================================
# bootstrap: setup.sh が最初に実行（ローカル state で作成後、S3 へ自動移行）
#   - Terraform 状態ファイル用 S3（S3 ネイティブロック利用のため DynamoDB 不要）
#   - GitHub Actions 用 OIDC プロバイダ（既存なら再利用）と CI ロール
#   - Claude Code 用の権限を絞った IAM ロール
# =============================================================
terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.80" }
  }
}

provider "aws" {
  region = "ap-northeast-1"
  default_tags { tags = { Project = "sample-app", ManagedBy = "terraform", Layer = "bootstrap" } }
}

variable "create_oidc_provider" {
  type    = bool
  default = true
}

locals {
  github_repo = "DaisukeKoike/sample-app"
  account_id  = "000000000000"
  region      = "ap-northeast-1"
}

# ---------- tfstate ----------
resource "aws_s3_bucket" "tfstate" {
  bucket = "sample-app-tfstate-000000000000"
}
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- GitHub OIDC ----------
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}
locals {
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repo}:pull_request", "repo:${local.github_repo}:ref:refs/heads/main"]
    }
  }
}
resource "aws_iam_role" "ci" {
  name               = "sample-app-github-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_trust.json
}
resource "aws_iam_role_policy_attachment" "ci_readonly" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
data "aws_iam_policy_document" "ci_state" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
  }
}
resource "aws_iam_role_policy" "ci_state" {
  name   = "tfstate"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_state.json
}

# ---------- Claude Code 用 ----------
# 課題別環境の5リソースとイメージ登録だけを許可。共有基盤・IAM は変更不可。
data "aws_iam_policy_document" "ai_dev" {
  statement {
    sid       = "State"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
  }
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrRepo"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:ListImages",
      "ecr:DescribeImages", "ecr:BatchDeleteImage"
    ]
    resources = ["arn:aws:ecr:${local.region}:${local.account_id}:repository/sample-app"]
  }
  statement {
    sid       = "ReadAll"
    actions   = ["ec2:Describe*", "elasticloadbalancing:Describe*", "ecs:Describe*", "ecs:List*", "route53:Get*", "route53:List*", "logs:Describe*", "iam:GetRole", "acm:Describe*", "acm:List*"]
    resources = ["*"]
  }
  statement {
    sid       = "EcsTaskDef"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:TagResource"]
    resources = ["*"]
  }
  statement {
    sid       = "EcsServiceIssue"
    actions   = ["ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService"]
    resources = ["arn:aws:ecs:${local.region}:${local.account_id}:service/sample-app-dev/issue-*"]
  }
  statement {
    sid = "ElbIssue"
    actions = [
      "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyRule", "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/ManagedBy"
      values   = ["issue-env"]
    }
  }
  statement {
    sid       = "ElbCreateTagged"
    actions   = ["elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:CreateRule", "elasticloadbalancing:AddTags"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/ManagedBy"
      values   = ["issue-env"]
    }
  }
  statement {
    sid       = "Route53Issue"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/*"]
    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["issue-*.dev.example.com"]
    }
  }
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/sample-app-dev-ecs-*"]
  }
}
resource "aws_iam_policy" "ai_dev" {
  name        = "sample-app-ai-developer"
  description = "Claude Code が使う認証情報用。課題別環境のみ操作可能"
  policy      = data.aws_iam_policy_document.ai_dev.json
}

data "aws_iam_policy_document" "ai_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}
resource "aws_iam_role" "ai_dev" {
  name                 = "sample-app-ai-developer"
  assume_role_policy   = data.aws_iam_policy_document.ai_trust.json
  max_session_duration = 43200
}
resource "aws_iam_role_policy_attachment" "ai_dev" {
  role       = aws_iam_role.ai_dev.name
  policy_arn = aws_iam_policy.ai_dev.arn
}

output "ci_role_arn" { value = aws_iam_role.ci.arn }
output "ai_dev_role_arn" { value = aws_iam_role.ai_dev.arn }
