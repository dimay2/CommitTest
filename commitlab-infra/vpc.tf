data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.app_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  
  # REQUIREMENT: "Only Private Subnets Allowed"
  # We removed public_subnets and NAT Gateways.
  # Traffic must go through VPC Endpoints.
  enable_nat_gateway   = false
  single_nat_gateway   = false
  enable_vpn_gateway   = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# --- VPC Endpoints (Required because we have no NAT/Internet) ---

resource "aws_security_group" "vpce" {
  name        = "${var.app_name}-vpce-sg"
  description = "Allow HTTPS from VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}

# S3 Gateway (Required for pulling container layers)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}

# Interface Endpoints for EKS, ECR, SSM, and Logging
locals {
  endpoints = [
    "ecr.api",              # ECR Control Plane
    "ecr.dkr",              # Docker Pulls
    "sts",                  # IAM Roles for Service Accounts
    "logs",                 # CloudWatch Logs
    "ssm",                  # Systems Manager (Jumpbox)
    "ec2messages",          # SSM Agent (Jumpbox)
    "ssmmessages",          # SSM Session Manager (Jumpbox)
    "ec2",                  # Needed for ALB Controller to discover subnets
    "elasticloadbalancing"  # Needed for ALB Controller to create ALBs
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each          = toset(local.endpoints)
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type = "Interface"
  subnet_ids        = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpce.id]
  private_dns_enabled = true
}