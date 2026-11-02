# =============================================================
# envs/issue: 課題別環境（ワークスペース issue-<番号> ごとに state を分離）
#   作るのは5つの軽いリソースだけ
#   1) ECS タスク定義 2) ECS サービス 3) ターゲットグループ 4) ALB リスナールール 5) Route53 レコード
# =============================================================
terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.80" }
  }
  backend "s3" {
    bucket       = "sample-app-tfstate-000000000000"
    key          = "issue-env/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}

variable "issue_id" {
  type = number
  validation {
    condition     = var.issue_id > 0 && var.issue_id < 50000
    error_message = "issue_id は 1〜49999 の課題番号"
  }
}
variable "image_tag" { type = string }

locals {
  name = "issue-${var.issue_id}"
  host = "${local.name}.dev.example.com"
}

check "workspace_matches_issue" {
  assert {
    condition     = terraform.workspace == local.name
    error_message = "ワークスペース(${terraform.workspace}) と issue_id(${var.issue_id}) が一致しません"
  }
}

provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = { Project = "sample-app", ManagedBy = "issue-env", Issue = tostring(var.issue_id) }
  }
}

data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = "sample-app-tfstate-000000000000"
    key    = "base/terraform.tfstate"
    region = "ap-northeast-1"
  }
}
locals { base = data.terraform_remote_state.base.outputs }

resource "aws_ecs_task_definition" "this" {
  family                   = "sample-app-${local.name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = local.base.execution_role_arn
  task_role_arn            = local.base.task_role_arn
  container_definitions = jsonencode([{
    name         = "app"
    image        = "${local.base.ecr_repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "APP_ENV", value = "issue" },
      { name = "ISSUE_ID", value = tostring(var.issue_id) },
      { name = "DB_SCHEMA", value = "issue_${var.issue_id}" },
      { name = "SEARCH_INDEX_PREFIX", value = "issue-${var.issue_id}-" },
      { name = "ENV_BANNER", value = "検証環境 #${var.issue_id}" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = local.base.log_group_name
        awslogs-region        = "ap-northeast-1"
        awslogs-stream-prefix = local.name
      }
    }
  }])
}

resource "aws_lb_target_group" "this" {
  name        = "${substr("sample-app", 0, 15)}-${local.name}" # 32文字制限
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.base.vpc_id
  health_check {
    path    = "/health"
    matcher = "200-399"
  }
  deregistration_delay = 10
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = local.base.listener_arn
  priority     = var.issue_id
  condition {
    host_header { values = [local.host] }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_ecs_service" "this" {
  name            = local.name
  cluster         = local.base.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = local.base.private_subnet_ids
    security_groups  = [local.base.task_security_group_id]
    assign_public_ip = false # NAT が無い VPC では true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "app"
    container_port   = 8080
  }
  deployment_minimum_healthy_percent = 0
  wait_for_steady_state              = true
  depends_on                         = [aws_lb_listener_rule.this]
}

resource "aws_route53_record" "this" {
  zone_id = local.base.zone_id
  name    = local.host
  type    = "A"
  alias {
    name                   = local.base.alb_dns_name
    zone_id                = local.base.alb_zone_id
    evaluate_target_health = false
  }
}

output "app_url" { value = "https://${local.host}" }
