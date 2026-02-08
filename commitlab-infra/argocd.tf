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

    # Server (argocd-server)
    server:
      replicas: 1
      image:
        repository: ${var.argocd_server_image != "" ? var.argocd_server_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-server"}
        tag: v2.9.8
      extraArgs:
        - --insecure

    # Repo server
    repoServer:
      replicas: 1
      image:
        repository: ${var.argocd_repo_server_image != "" ? var.argocd_repo_server_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-repo-server"}
        tag: v2.9.8

    # Application Controller
    applicationController:
      replicas: 1
      image:
        repository: ${var.argocd_application_controller_image != "" ? var.argocd_application_controller_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-application-controller"}
        tag: v2.9.8

    # ApplicationSet controller
    applicationSet:
      replicas: 1
      image:
        repository: ${var.argocd_applicationset_image != "" ? var.argocd_applicationset_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-applicationset-controller"}
        tag: v2.9.8

    # Dex (SSO)
    dex:
      enabled: true
      image:
        repository: ${var.argocd_dex_image != "" ? var.argocd_dex_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-dex-server"}
        tag: v2.9.8

    # Notifications controller
    notifications:
      image:
        repository: ${var.argocd_notifications_image != "" ? var.argocd_notifications_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-notifications-controller"}
        tag: v2.9.8

    # Redis (argocd-redis)
    redis:
      image:
        repository: ${var.argocd_redis_image != "" ? var.argocd_redis_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-redis"}
        tag: latest

    EOT
  ]
}