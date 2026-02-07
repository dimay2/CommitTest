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
  repository = "https://kubernetes.github.io/dashboard/"
  chart      = "kubernetes-dashboard"
  version    = "7.3.2"
  namespace  = "monitoring"

  # Wait for Metrics Server to be ready first
  depends_on = [helm_release.metrics_server]

  # Images pulled from private ECR for air-gapped environment
  values = [
    <<-EOT
    app:
      image:
        repository: ${var.kubernetes_dashboard_image != "" ? var.kubernetes_dashboard_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/kubernetes-dashboard"}
        tag: v2.7.0
    nginx:
      enabled: false
    cert-manager:
      enabled: false
    metricsScraper:
      enabled: true
    resources:
      requests:
        cpu: 100m
        memory: 200Mi
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