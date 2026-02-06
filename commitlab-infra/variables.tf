variable "aws_region" { type = string }
variable "vpc_cidr" { type = string }
variable "cluster_name" { type = string }
variable "app_name" { type = string }
variable "hosted_zone_name" { type = string }

# SECURITY: No default value. Must be provided via TF_VAR_db_password
variable "db_password" { 
  type        = string
  sensitive   = true 
  description = "RDS Root Password"
}