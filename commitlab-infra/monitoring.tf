# 1. Metrics Server (Required for Fargate & Dashboard to see CPU/RAM)
resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.12.1"
  namespace        = "monitoring"
  create_namespace = true

  values = [
    <<-EOT
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

  values = [
    <<-EOT
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