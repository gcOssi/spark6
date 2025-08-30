variable "project_name" {
  type    = string
  default = "staging-dashboard"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "az_count" {
  type    = number
  default = 2
}

# GitHub OIDC
variable "gh_owner" {
  type        = string
  description = "GitHub org/owner usado en el OIDC condition"
}

variable "gh_repo" {
  type        = string
  description = "GitHub repo usado en el OIDC condition"
}

variable "alarm_email" {
  type        = string
  description = "Email to subscribe to SNS alerts"
  default     = "gcabrera@binarios.cl"
}

# Basic auth for staging
variable "basic_auth_user" {
  type    = string
  default = "staging"
}

variable "basic_auth_password" {
  type    = string
  default = "staging"
}

# Alerts
variable "alert_email" {
  type = string
}

# HTTPS options
variable "acm_certificate_arn" {
  type        = string
  description = "Optional ACM certificate ARN for the ALB (if using your own domain). If empty, ALB will stay HTTP and CloudFront will provide HTTPS."
  default     = ""
}

variable "enable_cloudfront" {
  type        = bool
  default     = true
  description = "Wrap the ALB with CloudFront so the public endpoint is HTTPS even without ACM certificate."
}

variable "image_tag" {
  description = "Tag a publicar en ECR (usa latest o un SHA)"
  type        = string
  default     = "latest"
}

variable "build_platform" {
  description = "Plataforma para docker build; p.ej. linux/amd64 para Mac M1/M2"
  type        = string
  default     = "" # vacío = usa plataforma por defecto del Docker host
}

variable "react_app_api_url" {
  description = "Valor para REACT_APP_API_URL en el build del frontend"
  type        = string
  default     = ""
}

variable "force_ecs_redeploy" {
  description = "Forzar redeploy de ECS al terminar el push"
  type        = bool
  default     = true
}

variable "allowed_origins" {
  description = "Lista separada por comas de orígenes permitidos para CORS"
  type        = string
  default     = ""  # "" => auto
}

variable "cors_allow_credentials" {
  description = "Si el backend debe devolver Access-Control-Allow-Credentials: true"
  type        = bool
  default     = true
}

# ===== CORS (headers y métodos) =====
variable "cors_allow_headers" {
  description = "Headers permitidos por CORS"
  type        = string
  default     = "Content-Type,Authorization"
}

variable "cors_allow_methods" {
  description = "Métodos permitidos por CORS"
  type        = string
  default     = "GET,POST,PUT,PATCH,DELETE,OPTIONS"
}
