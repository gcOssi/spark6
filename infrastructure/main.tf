locals {
  name = var.project_name
  tags = {
    Project = var.project_name
    Stage   = "staging"
  }
}

# Origen público (CloudFront si está habilitado, sino ALB)
locals {
  public_origin = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.cdn[0].domain_name}" : "http://${aws_lb.alb.dns_name}"

  # Si var.allowed_origins viene vacío, autogenera con el dominio público + localhost
  allowed_origins_effective = trimspace(var.allowed_origins) != "" ? var.allowed_origins : "${local.public_origin},http://localhost:3000"
}


data "aws_caller_identity" "current" {}

# Reuse existing GitHub OIDC provider in the account (if already created)
data "aws_iam_openid_connect_provider" "github" {
  arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

######################
# Networking (VPC)  #
######################
data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name}-igw" })
}

# Public subnets for ALB
resource "aws_subnet" "public" {
  for_each = { for i, az in slice(data.aws_availability_zones.available.names, 0, var.az_count) : i => az }
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, each.key)
  availability_zone       = each.value
  map_public_ip_on_launch = true
  tags = merge(local.tags, { Name = "${local.name}-public-${each.value}", Tier = "public" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name}-public-rt" })
}

resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = { for i, az in slice(data.aws_availability_zones.available.names, 0, var.az_count) : i => az }
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}


# Private subnets for ECS tasks
resource "aws_subnet" "private" {
  for_each = { for i, az in slice(data.aws_availability_zones.available.names, 0, var.az_count) : i => az }
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 4, each.key + 8)
  availability_zone = each.value
  tags = merge(local.tags, { Name = "${local.name}-private-${each.value}", Tier = "private" })
}

resource "aws_eip" "nat" {
  tags = merge(local.tags, { Name = "${local.name}-nat-eip" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id
  tags          = merge(local.tags, { Name = "${local.name}-nat" })
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name}-private-rt" })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = { for i, az in slice(data.aws_availability_zones.available.names, 0, var.az_count) : i => az }
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private.id
}


######################
# Security Groups    #
######################
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB SG"
  vpc_id      = aws_vpc.main.id
  tags        = local.tags
}

# Allow inbound 80 and 443 (redirect 80->443 if cert provided)
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name}-ecs-sg"
  description = "ECS tasks SG"
  vpc_id      = aws_vpc.main.id
  tags        = local.tags
}

# ALB -> ECS tasks on port 80
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs_tasks.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs_tasks.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

######################
# ECR (images)       #
######################
resource "aws_ecr_repository" "frontend" {
  name = "${local.name}-frontend"
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
  force_delete = true
}
resource "aws_ecr_repository" "backend" {
  name = "${local.name}-backend"
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
  force_delete = true
}

######################
# IAM for ECS        #
######################
data "aws_iam_policy_document" "assume_task" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
        type        = "Service"
        identifiers = ["ecs-tasks.amazonaws.com"]
      }
  }
}

resource "aws_iam_role" "ecs_task_exec" {
  name               = "${local.name}-task-exec"
  assume_role_policy = data.aws_iam_policy_document.assume_task.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_policy" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${local.name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.assume_task.json
  tags               = local.tags
}

# Allow SSM parameter access for secrets
data "aws_iam_policy_document" "task_ssm_access" {
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      aws_ssm_parameter.basic_auth_user.arn,
      aws_ssm_parameter.basic_auth_password.arn
    ]
  }
}
resource "aws_iam_policy" "task_ssm_access" {
  name   = "${local.name}-task-ssm"
  policy = data.aws_iam_policy_document.task_ssm_access.json
}
resource "aws_iam_role_policy_attachment" "task_ssm_access_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.task_ssm_access.arn
}

# --- Allow the **execution role** to read SSM params and decrypt KMS for ECS secrets bootstrap
data "aws_iam_policy_document" "exec_ssm_access" {
  statement {
    sid     = "AllowReadBasicAuthParams"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      aws_ssm_parameter.basic_auth_user.arn,
      aws_ssm_parameter.basic_auth_password.arn
    ]
  }
  statement {
    sid     = "AllowKMSDecryptForSSM"
    actions = ["kms:Decrypt"]
    resources = ["*"]
    # (Opcional) Puedes restringir a tu CMK si usas una clave propia en vez de la administrada
  }
}

resource "aws_iam_policy" "exec_ssm_access" {
  name   = "${local.name}-exec-ssm"
  policy = data.aws_iam_policy_document.exec_ssm_access.json
}

resource "aws_iam_role_policy_attachment" "exec_ssm_access_attach" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = aws_iam_policy.exec_ssm_access.arn
}


######################
# Logs               #
######################
resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.name}/frontend"
  retention_in_days = 14
  tags              = local.tags
}
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name}/backend"
  retention_in_days = 14
  tags              = local.tags
}

######################
# SSM Parameters     #
######################
resource "aws_ssm_parameter" "basic_auth_user" {
  name  = "/${local.name}/basic_auth/user"
  type  = "SecureString"
  value = var.basic_auth_user
  tags  = local.tags
}
resource "aws_ssm_parameter" "basic_auth_password" {
  name  = "/${local.name}/basic_auth/password"
  type  = "SecureString"
  value = var.basic_auth_password
  tags  = local.tags
}

######################
# ALB                #
######################
resource "aws_lb" "alb" {
  name               = "${replace(local.name, "/[^a-zA-Z0-9-]/", "-")}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]
  tags               = local.tags
}

resource "aws_lb_target_group" "tg" {
  name        = "${substr(replace(local.name, "/[^a-zA-Z0-9-]/", "-"),0,26)}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = local.tags
}

# HTTP listener (redirect to HTTPS if cert provided)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = var.acm_certificate_arn == "" ? "forward" : "redirect"
    target_group_arn = var.acm_certificate_arn == "" ? aws_lb_target_group.tg.arn : null
    redirect {
      protocol = "HTTPS"
      port     = "443"
      status_code = "HTTP_301"
    }
  }
}

# Optional HTTPS listener
resource "aws_lb_listener" "https" {
  count             = var.acm_certificate_arn == "" ? 0 : 1
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

######################
# ECS Cluster/Task   #
######################
resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags  = local.tags
}

# Task Definition (2 containers: frontend nginx + backend node)
data "aws_ecr_repository" "frontend" { name = aws_ecr_repository.frontend.name }
data "aws_ecr_repository" "backend"  { name = aws_ecr_repository.backend.name  }

locals {
  frontend_image = "${data.aws_ecr_repository.frontend.repository_url}:latest"
  backend_image  = "${data.aws_ecr_repository.backend.repository_url}:latest"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_exec.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      "name": "frontend",
      "image": local.frontend_image,
      "portMappings": [{"containerPort": 80, "hostPort": 80, "protocol": "tcp"}],
      "essential": true,
      "environment": [
        {"name": "PROXY_API_URL", "value": "http://127.0.0.1:4000"},
          {"name": "PORT", "value": "4000"},
          {"name": "ALLOWED_ORIGINS",        "value": local.allowed_origins_effective},
          {"name": "CORS_ALLOW_CREDENTIALS", "value": tostring(var.cors_allow_credentials)},
          {"name": "CORS_ALLOW_HEADERS",     "value": var.cors_allow_headers},
          {"name": "CORS_ALLOW_METHODS",     "value": var.cors_allow_methods}
      ],
      "secrets": [
        {"name": "BASIC_AUTH_USER",     "valueFrom": aws_ssm_parameter.basic_auth_user.arn},
        {"name": "BASIC_AUTH_PASSWORD", "valueFrom": aws_ssm_parameter.basic_auth_password.arn}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": aws_cloudwatch_log_group.frontend.name,
          "awslogs-region": var.aws_region,
          "awslogs-stream-prefix": "ecs"
        }
      }
    },
    {
      "name": "backend",
      "image": local.backend_image,
      "essential": true,
      "portMappings": [{"containerPort": 4000, "hostPort": 4000, "protocol": "tcp"}],
      "environment": [
        {"name": "PORT", "value": "4000"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": aws_cloudwatch_log_group.backend.name,
          "awslogs-region": var.aws_region,
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "wget -qO- http://127.0.0.1:4000/api/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 40
      }
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  tags = local.tags
}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = [for s in aws_subnet.private : s.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "frontend"
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
  tags       = local.tags
}

######################
# Alerts (CPU > 70%) #
######################
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
  tags = local.tags
}
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name}-cpu-high"
  alarm_description   = "ECS service CPU > 70%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 70
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  statistic           = "Average"
  period              = 300

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

######################
# CloudFront (HTTPS) #
######################
resource "aws_cloudfront_distribution" "cdn" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  comment             = "${local.name} staging CDN"
  is_ipv6_enabled     = true
  default_root_object = ""

  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = "alb-origin"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

default_cache_behavior {
  target_origin_id       = "alb-origin"
  viewer_protocol_policy = "redirect-to-https"

  # Métodos permitidos
  allowed_methods = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
  cached_methods  = ["GET","HEAD"]

  forwarded_values {
    query_string = true
    headers      = ["*"]
    cookies {
      forward = "all"
    }
  }

  # TTLs en cero => sin caché
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 0
}



  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

######################
# GitHub OIDC Role   #
######################
data "aws_iam_policy_document" "gha_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:{var.github_owner}/${var.github_repo}:environment:staging","repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"]
    }
  }
}



resource "aws_iam_role" "gha_deploy_role" {
  name               = "${local.name}-gha"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
  tags               = local.tags
}

# Permissions for CI/CD: ECR, ECS, CloudWatch Logs, and Describe*
data "aws_iam_policy_document" "gha_policy" {
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:CreateRepository"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecs:DescribeClusters",
      "ecs:DescribeServices",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions"
    ]
    resources = ["*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_task_exec.arn, aws_iam_role.ecs_task_role.arn]
  }
  statement {
    actions = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gha_policy" {
  name   = "${local.name}-gha-policy"
  policy = data.aws_iam_policy_document.gha_policy.json
}
resource "aws_iam_role_policy_attachment" "gha_attach" {
  role       = aws_iam_role.gha_deploy_role.name
  policy_arn = aws_iam_policy.gha_policy.arn
}

######################
# Outputs            #
######################
output "alb_dns" {
  value = aws_lb.alb.dns_name
}
output "cloudfront_domain" {
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.cdn[0].domain_name : ""
  description = "Public HTTPS endpoint (if CloudFront enabled)"
}
output "ecr_frontend" { value = aws_ecr_repository.frontend.repository_url }
output "ecr_backend"  { value = aws_ecr_repository.backend.repository_url  }
output "ecs_cluster"  { value = aws_ecs_cluster.this.name }
output "ecs_service"  { value = aws_ecs_service.app.name }
output "github_actions_role_arn" { value = aws_iam_role.gha_deploy_role.arn }
