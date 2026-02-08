# ECR Repositories for Kubernetes Dashboard v7+ (Microservices)

resource "aws_ecr_repository" "kubernetes_dashboard_api" {
  name                 = "kubernetes-dashboard-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "kubernetes_dashboard_web" {
  name                 = "kubernetes-dashboard-web"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "kubernetes_dashboard_metrics_scraper" {
  name                 = "kubernetes-dashboard-metrics-scraper"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "kong" {
  name                 = "kong"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}