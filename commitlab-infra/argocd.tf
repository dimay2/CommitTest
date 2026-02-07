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
  # Images pulled from private ECR for air-gapped environment
  values = [
    <<-EOT
    redis-ha:
      enabled: false
    controller:
      replicas: 1
    server:
      replicas: 1
      image:
        repository: ${var.argocd_server_image != "" ? var.argocd_server_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-server"}
        tag: v2.9.8
      extraArgs:
        - --insecure # Disables internal TLS to simplify jumpbox access/ingress
    repoServer:
      replicas: 1
      image:
        repository: ${var.argocd_repo_server_image != "" ? var.argocd_repo_server_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-repo-server"}
        tag: v2.9.8
    applicationController:
      replicas: 1
    applicationSet:
      replicas: 1
    EOT
  ]
}