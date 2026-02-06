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