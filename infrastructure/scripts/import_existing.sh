#!/usr/bin/env bash
set -euo pipefail

# Nombre base (debe coincidir con var.project_name => "staging-dashboard" por defecto)
NAME="${1:-staging-dashboard}"

tf_show() { terraform state show "$1" >/dev/null 2>&1; }
tf_import_if_missing() {
  local addr="$1" id="$2"
  tf_show "$addr" || terraform import -no-color "$addr" "$id" || true
}

# ECR
aws ecr describe-repositories --repository-names "${NAME}-frontend" >/dev/null 2>&1 && \
  tf_import_if_missing aws_ecr_repository.frontend "${NAME}-frontend"
aws ecr describe-repositories --repository-names "${NAME}-backend" >/dev/null 2>&1 && \
  tf_import_if_missing aws_ecr_repository.backend  "${NAME}-backend"

# IAM Roles
aws iam get-role --role-name "${NAME}-task-exec" >/dev/null 2>&1 && \
  tf_import_if_missing aws_iam_role.ecs_task_exec "${NAME}-task-exec"
aws iam get-role --role-name "${NAME}-task-role" >/dev/null 2>&1 && \
  tf_import_if_missing aws_iam_role.ecs_task_role  "${NAME}-task-role"

# Log Groups
aws logs describe-log-groups --log-group-name-prefix "/ecs/${NAME}/frontend" \
  --query 'logGroups[?logGroupName==`/ecs/'"${NAME}"'/frontend`]' --output text | \
  grep -q "/ecs/${NAME}/frontend" && \
  tf_import_if_missing aws_cloudwatch_log_group.frontend "/ecs/${NAME}/frontend"

aws logs describe-log-groups --log-group-name-prefix "/ecs/${NAME}/backend" \
  --query 'logGroups[?logGroupName==`/ecs/'"${NAME}"'/backend`]' --output text | \
  grep -q "/ecs/${NAME}/backend" && \
  tf_import_if_missing aws_cloudwatch_log_group.backend "/ecs/${NAME}/backend"

# ALB / TG
alb_arn=$(aws elbv2 describe-load-balancers --names "${NAME}-alb" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
[ -n "$alb_arn" ] && tf_import_if_missing aws_lb.alb "$alb_arn"

# Si tu TG usa truncado a 26 chars + "-tg", replicamos esa lógica:
TG_BASENAME=$(echo "$NAME" | sed 's/[^a-zA-Z0-9-]/-/g' | cut -c1-26)
TG_NAME="${TG_BASENAME}-tg"
tg_arn=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
[ -n "$tg_arn" ] && tf_import_if_missing aws_lb_target_group.tg "$tg_arn"

# SSM Parameters
aws ssm get-parameter --name "/${NAME}/basic_auth/user" >/dev/null 2>&1 && \
  tf_import_if_missing aws_ssm_parameter.basic_auth_user "/${NAME}/basic_auth/user"
aws ssm get-parameter --name "/${NAME}/basic_auth/password" >/dev/null 2>&1 && \
  tf_import_if_missing aws_ssm_parameter.basic_auth_password "/${NAME}/basic_auth/password"

echo "✅ Imports idempotentes completados (si correspondía)."