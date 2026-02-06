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
