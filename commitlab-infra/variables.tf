variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS Cluster"
  type        = string
}

variable "app_name" {
  description = "Base name for application resources"
  type        = string
}

variable "hosted_zone_name" {
  description = "The Private DNS Zone name (e.g., commit.local)"
  type        = string
}

variable "db_password" { 
  type        = string
  sensitive   = true 
  description = "RDS Root Password"
}

variable "environment_tag" {
  description = "Environment tag for all resources"
  type        = string
  default     = "dimatest"
}