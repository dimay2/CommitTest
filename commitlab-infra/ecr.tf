# Private ECR Repositories for Air-Gapped Cluster
# These repos will hold mirrored images for Helm charts and applications
# accessible by Fargate pods via VPC Endpoints

# ArgoCD Server
resource "aws_ecr_repository" "argocd_server" {
  name                       = "argocd-server"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-argocd-server" }
}

# ArgoCD Repo Server
resource "aws_ecr_repository" "argocd_repo_server" {
  name                       = "argocd-repo-server"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-argocd-repo-server" }
}

# ArgoCD Application Controller
resource "aws_ecr_repository" "argocd_application_controller" {
  name                       = "argocd-application-controller"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-argocd-application-controller" }
}

# ArgoCD ApplicationSet Controller
resource "aws_ecr_repository" "argocd_applicationset_controller" {
  name                       = "argocd-applicationset-controller"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-argocd-applicationset-controller" }
}

# ArgoCD Notifications Controller
resource "aws_ecr_repository" "argocd_notifications_controller" {
  name                       = "argocd-notifications-controller"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-argocd-notifications-controller" }
}

# ArgoCD Dex Server
resource "aws_ecr_repository" "argocd_dex_server" {
  name                       = "argocd-dex-server"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-argocd-dex-server" }
}

# ArgoCD Redis
resource "aws_ecr_repository" "argocd_redis" {
  name                       = "argocd-redis"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-argocd-redis" }
}

# Metrics Server (for Kubernetes Dashboard and Pod Metrics)
resource "aws_ecr_repository" "metrics_server" {
  name                       = "metrics-server"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-metrics-server" }
}

# Kubernetes Dashboard
resource "aws_ecr_repository" "kubernetes_dashboard" {
  name                       = "kubernetes-dashboard"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-kubernetes-dashboard" }
}

# AWS Load Balancer Controller
resource "aws_ecr_repository" "aws_load_balancer_controller" {
  name                       = "aws-load-balancer-controller"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-aws-load-balancer-controller" }
}

# Application Backend
resource "aws_ecr_repository" "lab_backend" {
  name                       = "lab-backend"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-lab-backend" }
}

# Application Frontend
resource "aws_ecr_repository" "lab_frontend" {
  name                       = "lab-frontend"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-lab-frontend" }
}

# CoreDNS (if needed for custom DNS setup)
resource "aws_ecr_repository" "coredns" {
  name                       = "coredns"
  image_tag_mutability       = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = { Name = "${var.app_name}-coredns" }
}

# Lifecycle policies: Auto-delete old images to control storage costs
# Keep only the last 10 images per repo
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each = toset([
    aws_ecr_repository.argocd_server.name,
    aws_ecr_repository.argocd_repo_server.name,
    aws_ecr_repository.argocd_application_controller.name,
    aws_ecr_repository.argocd_applicationset_controller.name,
    aws_ecr_repository.argocd_notifications_controller.name,
    aws_ecr_repository.argocd_dex_server.name,
    aws_ecr_repository.argocd_redis.name,
    aws_ecr_repository.metrics_server.name,
    aws_ecr_repository.kubernetes_dashboard.name,
    aws_ecr_repository.aws_load_balancer_controller.name,
    aws_ecr_repository.lab_backend.name,
    aws_ecr_repository.lab_frontend.name,
    aws_ecr_repository.coredns.name
  ])

  repository = each.value
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus             = "any"
        countType             = "imageCountMoreThan"
        countNumber           = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
