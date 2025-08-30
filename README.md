# Staging: ECS Fargate + ALB (+ optional CloudFront) with CI/CD and Basic Auth

This repo is ready to deploy a **React frontend + Node.js API** (Dockerized) on **AWS ECS Fargate**, fronted by an **ALB** and optionally **CloudFront** (for HTTPS without a custom domain). The frontend runs behind **HTTP Basic Auth** and proxies `/api` to the backend, keeping the API private.

## Architecture (high level)
- **VPC** with public subnets (ALB) and private subnets (ECS tasks, outbound via NAT)
- **ECS Fargate task** with **two containers**:
  - `frontend`: **nginx** serves the React build and enforces **Basic Auth** for all paths. Proxies `/api/*` to `http://127.0.0.1:4000`.
  - `backend`: Node.js API on port 4000 (only reachable from the `frontend` container in the same task).
- **ALB** forwards `:80` (and `:443` if ACM is provided) to the `frontend` container.
- **CloudFront (optional)** sits in front of the ALB and redirects HTTP→HTTPS so your **public URL is always HTTPS** even without a custom domain.
- **ECR** for images, **SSM Parameter Store** for credentials, **CloudWatch** logs & **CPU alarm** (>70%) → **SNS email**.

## Local development
Keep your local docker-compose as reference. In our setup, healthcheck and ports align with your current compose (backend at `/api/health`, frontend on `80`). Update your `.env` as needed. For example, your compose includes a backend health check at `http://localhost:4000/api/health` and a frontend build serving on 80.

## One-time setup (Terraform)
1. Edit `infrastructure/variables.tf` (or set via `-var`) for:
   - `github_owner`, `github_repo`
   - `alert_email`
   - Optionally `acm_certificate_arn` (if you have a domain) and/or `enable_cloudfront` (default `true`).
2. Initialize and apply:
   ```bash
   cd infrastructure
   terraform init
   terraform apply -auto-approve
   ```
3. Note the outputs. Copy **`github_actions_role_arn`** and save it as a repo secret `AWS_DEPLOY_ROLE_ARN`.

## CI/CD (GitHub Actions)
- On push to `main`, the workflow:
  1) assumes the AWS role (OIDC), 2) logs in to ECR, 3) builds & pushes images, 4) registers a new **task definition** revision, and 5) **forces a new deployment** of the ECS service.
- You must set these repo secrets:
  - `AWS_DEPLOY_ROLE_ARN` → from Terraform output `github_actions_role_arn`.

## Basic Auth
- Credentials are stored in **SSM**:
  - `/${project_name}/basic_auth/user`
  - `/${project_name}/basic_auth/password`
- The `frontend` entrypoint creates `/etc/nginx/.htpasswd` at runtime. All routes (including `/api`) require Basic Auth.


## Monitoring
- CloudWatch alarm: **CPUUtilization > 70%** (2×5min) → SNS email to `var.alert_email`.


## Diagrams & screenshots
- See `docs/arch-diagram.mmd` (Mermaid).
- Screenshots in `docs/screenshots/`.

## Notes
- The ECS service is created by Terraform and later **updated by the CI** (new task definition revisions). This is a common pattern for combining IaC + CD. If you re-apply Terraform later, it won't roll back image tags due to the `ignore_changes` lifecycle on the service.
