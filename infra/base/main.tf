# =============================================================
# base: 共有基盤（常設）。人が操作する。AI の Hook / 権限では操作不可。
#   既存 VPC を参照し、ECS クラスタ・ECR・ALB(HTTPS, ワイルドカード証明書)・実行ロールを用意
# =============================================================
terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.80" }
  }
  backend "s3" {
    bucket       = "sample-app-tfstate-000000000000"
    key          = "base/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "ap-northeast-1"
  default_tags { tags = { Project = "sample-app", ManagedBy = "terraform", Layer = "base" } }
}

locals {
  name               = "sample-app-dev"
  vpc_id             = "vpc-unset"
  public_subnet_ids = [
    "subnet-unset1",
    "subnet-unset2",
  ]
  private_subnet_ids = [
    "subnet-unset1",
    "subnet-unset2",
  ]
  base_domain        = "dev.example.com"
}

data "aws_route53_zone" "this" {
  name = "example.com"
}

resource "aws_ecr_repository" "app" {
  name                 = "sample-app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1, description = "issue images older than 30 days"
      selection    = { tagStatus = "tagged", tagPrefixList = ["issue-"], countType = "sinceImagePushed", countUnit = "days", countNumber = 30 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecs_cluster" "this" {
  name = local.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

data "aws_iam_policy_document" "ecs_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
}
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role" "task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
  # アプリが使う Aurora / OpenSearch / S3 等への権限はここに追加する
}

resource "aws_cloudwatch_log_group" "issue" {
  name              = "/ecs/${local.name}/issue"
  retention_in_days = 14
}

resource "aws_security_group" "alb" {
  name   = "${local.name}-alb"
  vpc_id = local.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 社内限定にする場合は社内 CIDR に変更
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "task" {
  name   = "${local.name}-task"
  vpc_id = local.vpc_id
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${local.base_domain}"
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}
resource "aws_route53_record" "cert" {
  for_each        = { for o in aws_acm_certificate.wildcard.domain_validation_options : o.domain_name => o }
  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.cert : r.fqdn]
}

resource "aws_lb" "this" {
  name               = substr(local.name, 0, 32)
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.wildcard.certificate_arn
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "issue environment not found"
      status_code  = "404"
    }
  }
}

output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "listener_arn" { value = aws_lb_listener.https.arn }
output "alb_dns_name" { value = aws_lb.this.dns_name }
output "alb_zone_id" { value = aws_lb.this.zone_id }
output "vpc_id" { value = local.vpc_id }
output "private_subnet_ids" { value = local.private_subnet_ids }
output "task_security_group_id" { value = aws_security_group.task.id }
output "execution_role_arn" { value = aws_iam_role.execution.arn }
output "task_role_arn" { value = aws_iam_role.task.arn }
output "log_group_name" { value = aws_cloudwatch_log_group.issue.name }
output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "zone_id" { value = data.aws_route53_zone.this.zone_id }
