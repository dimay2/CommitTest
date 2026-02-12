# Fetch the CodeBuild IAM role. 
# NOTE: Ensure the 'name' matches your actual CodeBuild service role name in IAM.
data "aws_iam_role" "codebuild" {
  name = "${var.app_name}-codebuild-service-role" 
}

# Allow CodeBuild to access the EKS Cluster
resource "aws_eks_access_entry" "codebuild" {
  cluster_name      = var.cluster_name
  principal_arn     = data.aws_iam_role.codebuild.arn
  type              = "STANDARD"
}

# Grant Cluster Admin permissions to CodeBuild
resource "aws_eks_access_policy_association" "codebuild_admin" {
  cluster_name      = var.cluster_name
  policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn     = data.aws_iam_role.codebuild.arn
  access_scope {
    type = "cluster"
  }
}