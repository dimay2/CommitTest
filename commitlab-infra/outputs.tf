output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS Region"
  value       = var.aws_region
}

output "rds_endpoint" {
  description = "RDS Endpoint"
  value       = aws_db_instance.default.address
}

# Required for the update-dns.sh script to locate the Private Zone
output "hosted_zone_id" {
  description = "The ID of the Private Route53 Hosted Zone"
  value       = aws_route53_zone.private.zone_id
}

# Optional: Useful for Helm installation to know the ARN automatically
output "acm_certificate_arn" {
  description = "ARN of the self-signed certificate"
  value       = aws_acm_certificate.imported_cert.arn
}

# ECR Repository URIs for image mirroring (private registries for air-gapped cluster)
output "ecr_repository_urls" {
  description = "ECR repository URIs for mirroring images into air-gapped cluster"
  value = {
    argocd_server                       = aws_ecr_repository.argocd_server.repository_url
    argocd_repo_server                  = aws_ecr_repository.argocd_repo_server.repository_url
    argocd_application_controller       = aws_ecr_repository.argocd_application_controller.repository_url
    argocd_applicationset_controller    = aws_ecr_repository.argocd_applicationset_controller.repository_url
    argocd_notifications_controller     = aws_ecr_repository.argocd_notifications_controller.repository_url
    argocd_dex_server                   = aws_ecr_repository.argocd_dex_server.repository_url
    argocd_redis                        = aws_ecr_repository.argocd_redis.repository_url
    metrics_server                      = aws_ecr_repository.metrics_server.repository_url
    kubernetes_dashboard                = aws_ecr_repository.kubernetes_dashboard.repository_url
    aws_load_balancer_controller        = aws_ecr_repository.aws_load_balancer_controller.repository_url
    lab_backend                         = aws_ecr_repository.lab_backend.repository_url
    lab_frontend                        = aws_ecr_repository.lab_frontend.repository_url
    coredns                             = aws_ecr_repository.coredns.repository_url
  }
}

# AWS Account ID (useful for constructing ECR URIs)
output "aws_account_id" {
  description = "AWS Account ID for ECR URI construction"
  value       = data.aws_caller_identity.current.account_id
}