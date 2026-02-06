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

output "acm_certificate_arn" {
  description = "The ARN of the self-signed ACM certificate for the Ingress"
  value       = aws_acm_certificate.imported_cert.arn
}