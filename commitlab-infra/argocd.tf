resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "6.7.11" # Pinning a stable version
  namespace        = "argocd"
  create_namespace = true

  # Wait for Fargate to spin up resources
  timeout = 600

  # Basic HA disabled for lab efficiency; Fargate compatibility
  values = [
    <<-EOT
    redis-ha:
      enabled: false
    controller:
      replicas: 1
    server:
      replicas: 1
      extraArgs:
        - --insecure # Disables internal TLS to simplify jumpbox access/ingress
    repoServer:
      replicas: 1
    applicationSet:
      replicas: 1
    EOT
  ]
}