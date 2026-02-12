resource "helm_release" "argocd" {
  name             = "argocd"
  chart            = "${path.module}/charts/argo-cd"
  version          = "6.7.11" # Pinning a stable version
  namespace        = "argocd"
  create_namespace = true
  force_update     = true

  # Wait for Fargate to spin up resources
  timeout = 600

  # Basic HA disabled for lab efficiency; Fargate compatibility
  # Images pulled from private ECR for air-gapped environment
  values = [
    <<-EOT
    redis-ha:
      enabled: false

    configs:
      params:
        "server.insecure": "true"

    # Global image override to ensure chart uses private ECR for quay.io/argoproj/argocd images
    global:
      image:
        repository: ${var.argocd_global_image_repo != "" ? var.argocd_global_image_repo : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-server"}
        tag: v2.10.6

    # Server (argocd-server)
    server:
      replicas: 1
      service:
        # Force the Service's HTTPS port (443) to forward to the Pod's HTTP port (8080)
        # This allows the ALB to talk to port 443 on the Service, but reach the insecure app.
        targetPortHttps: 8080

      # Ingress is managed via Terraform in argocd_ingress.tf
      ingress:
        enabled: false

      image:
        repository: ${var.argocd_server_image != "" ? var.argocd_server_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-server"}
        tag: v2.10.6

    # Repo server
    repoServer:
      replicas: 1
      image:
        repository: ${var.argocd_repo_server_image != "" ? var.argocd_repo_server_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-repo-server"}
        tag: v2.10.6

    # Application Controller (Chart key is 'controller')
    controller:
      replicas: 1
      image:
        repository: ${var.argocd_application_controller_image != "" ? var.argocd_application_controller_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-application-controller"}
        tag: v2.10.6

    # ApplicationSet controller
    applicationSet:
      replicas: 1
      image:
        repository: ${var.argocd_applicationset_image != "" ? var.argocd_applicationset_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-applicationset-controller"}
        tag: v2.10.6

    # Dex (SSO)
    dex:
      enabled: true
      image:
        # Explicitly use argocd-dex-server from ECR (overrides global)
        repository: ${var.argocd_dex_image != "" ? var.argocd_dex_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-dex-server"}
        tag: v2.38.0

    # Notifications controller
    notifications:
      image:
        repository: ${var.argocd_notifications_image != "" ? var.argocd_notifications_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-notifications-controller"}
        tag: v2.10.6

    # Redis (argocd-redis)
    redis:
      image:
        repository: ${var.argocd_redis_image != "" ? var.argocd_redis_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-redis"}
        tag: 7.0.14-alpine

    EOT
  ]
}