data "aws_ecr_authorization_token" "token" {}

# 1. Metrics Server (Required for Fargate & Dashboard to see CPU/RAM)
resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.12.1"
  namespace        = "monitoring"
  create_namespace = true

  # Images pulled from private ECR for air-gapped environment
  values = [
    <<-EOT
    image:
      repository: ${var.metrics_server_image != "" ? var.metrics_server_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/metrics-server"}
      tag: v0.6.4
    args:
      - --kubelet-insecure-tls
    resources:
      requests:
        cpu: 100m
        memory: 200Mi
    EOT
  ]
}

# 2. Kubernetes Dashboard (The UI to "surf" to)
resource "helm_release" "kubernetes_dashboard" {
  name       = "kubernetes-dashboard"
  repository = var.kubernetes_dashboard_chart_repo == "" ? "oci://${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com" : var.kubernetes_dashboard_chart_repo
  chart      = var.kubernetes_dashboard_chart
  version    = "7.3.2"
  namespace  = "monitoring"
  repository_username = data.aws_ecr_authorization_token.token.user_name
  repository_password = data.aws_ecr_authorization_token.token.password

  # Wait for Metrics Server to be ready first
  depends_on = [helm_release.metrics_server]

  # Images pulled from private ECR for air-gapped environment
  values = [
    <<-EOT
    api:
      image:
        repository: ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/kubernetes-dashboard-api
        tag: 1.4.0
    web:
      image:
        repository: ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/kubernetes-dashboard-web
        tag: 1.4.0
    metricsScraper:
      enabled: true
      image:
        repository: ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/kubernetes-dashboard-metrics-scraper
        tag: 1.1.1
    kong:
      image:
        repository: ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/kong
        tag: 3.6
    EOT
  ]
}

# 3. Create a ServiceAccount for Admin Access (Dashboard requires a Token)
resource "kubernetes_service_account" "dashboard_admin" {
  metadata {
    name      = "admin-user"
    namespace = "monitoring"
  }
  depends_on = [helm_release.kubernetes_dashboard]
}

resource "kubernetes_cluster_role_binding" "dashboard_admin" {
  metadata {
    name = "admin-user"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.dashboard_admin.metadata.0.name
    namespace = "monitoring"
  }
}