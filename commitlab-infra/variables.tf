variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS Cluster"
  type        = string
}

variable "app_name" {
  description = "Base name for application resources"
  type        = string
}

variable "hosted_zone_name" {
  description = "The Private DNS Zone name (e.g., commit.local)"
  type        = string
}

variable "db_password" { 
  type        = string
  sensitive   = true 
  description = "RDS Root Password"
}

variable "environment_tag" {
  description = "Environment tag for all resources"
  type        = string
  default     = "dimatest"
}

# ============================================================================
# Private ECR Image Configuration
# For air-gapped environments, all Helm chart images must be mirrored to
# private ECR repositories before deployment. Set these to your private ECR URIs.
# ============================================================================

variable "enable_private_ecr_images" {
  description = "Enable private ECR image pull for all Helm charts (air-gapped mode)"
  type        = bool
  default     = true
}

variable "ecr_registry" {
  description = "Private ECR registry URL (e.g., 123456789012.dkr.ecr.eu-north-1.amazonaws.com)"
  type        = string
  default     = "" # Will be constructed from account_id and region if empty
}

variable "argocd_server_image" {
  description = "ArgoCD server image URI (private ECR)"
  type        = string
  default     = ""
}

variable "argocd_repo_server_image" {
  description = "ArgoCD repo server image URI (private ECR)"
  type        = string
  default     = ""
}

variable "argocd_application_controller_image" {
  description = "ArgoCD application controller image URI (private ECR)"
  type        = string
  default     = ""
}

variable "argocd_applicationset_image" {
  description = "ArgoCD ApplicationSet controller image URI (private ECR)"
  type        = string
  default     = ""
}

variable "argocd_dex_image" {
  description = "ArgoCD Dex (SSO) image URI (private ECR)"
  type        = string
  default     = ""
}

variable "argocd_notifications_image" {
  description = "ArgoCD notifications controller image URI (private ECR)"
  type        = string
  default     = ""
}

variable "argocd_redis_image" {
  description = "ArgoCD redis image URI (private ECR)"
  type        = string
  default     = ""
}

variable "argocd_global_image_repo" {
  description = "Global ArgoCD image repository base (private ECR). If empty, constructed from account and region to use 'argocd' repo."
  type        = string
  default     = ""
}

variable "metrics_server_image" {
  description = "Metrics server image URI (private ECR)"
  type        = string
  default     = ""
}

variable "kubernetes_dashboard_image" {
  description = "Kubernetes dashboard image URI (private ECR)"
  type        = string
  default     = ""
}

# Optional Helm chart source controls for air-gapped environments
variable "kubernetes_dashboard_chart_repo" {
  description = "Helm chart repository URL for Kubernetes Dashboard. Set to empty string to use a local chart archive."
  type        = string
  default     = "https://kubernetes.github.io/dashboard/"
}

variable "kubernetes_dashboard_chart" {
  description = "Helm chart name (or local chart directory/archive path) for Kubernetes Dashboard. If `kubernetes_dashboard_chart_repo` is empty, set this to a local chart archive path."
  type        = string
  default     = "kubernetes-dashboard"
}
