################################################################################
# AWS EKS Cluster Configuration (Strictly Private / Air-Gapped)
#
# IMPORTANT: All pod images (Helm releases, applications) are configured to
# pull from PRIVATE ECR repositories ONLY. This enforces air-gap security.
#
# Image pull workflow:
# 1. Mirror upstream images to private ECR using scripts/mirror-images.sh
# 2. Terraform Helm releases reference private ECR URIs (see argocd.tf, monitoring.tf)
# 3. Fargate pods pull images from VPC endpoints (no Internet access)
#
# See README section "Important: Private ECR image enforcement" for details.
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.10"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true
  enable_cluster_creator_admin_permissions = true
  authentication_mode = "API_AND_CONFIG_MAP"

  # Updated Fargate Profile to include 'argocd'
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        { namespace = "default" },
        { namespace = "kube-system" },
        { namespace = "monitoring" },
        { namespace = "argocd" }
      ]
    }
  }
}

module "lb_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"
  
  role_name = "${var.cluster_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}