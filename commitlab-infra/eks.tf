module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.10" # May 2024 Stable (v20 support for 1.30)

  cluster_name    = var.cluster_name
  cluster_version = "1.30" # STRICT REQUIREMENT

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # Ensure creator has admin permissions
  enable_cluster_creator_admin_permissions = true
  
  # Use API_AND_CONFIG_MAP for maximum compatibility
  authentication_mode = "API_AND_CONFIG_MAP"

  # Fargate Profile configuration
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        { namespace = "default" },
        { namespace = "kube-system" },
        { namespace = "monitoring" }
      ]
    }
  }
}

module "lb_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39" # May 2024 Stable
  
  role_name                              = "${var.cluster_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
