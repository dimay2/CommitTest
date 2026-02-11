data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# 1. Create ECR Repository for the CodeBuild custom builder image
resource "aws_ecr_repository" "codebuild_builder" {
  name                 = "codebuild-builder"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# 2. Build and Push the Docker image using local-exec
# This runs on the machine executing Terraform (Management Host)
resource "null_resource" "build_and_push_builder" {
  triggers = {
    # Re-run this resource only if the Dockerfile changes
    dockerfile_hash = filemd5("${path.module}/../builder/Dockerfile")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      ECR_URL="${aws_ecr_repository.codebuild_builder.repository_url}"
      REGION="${data.aws_region.current.name}"
      
      # Login to ECR
      aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL
      
      # Build and Push
      cd ../builder
      docker build -t $${ECR_URL}:latest .
      docker push $${ECR_URL}:latest
    EOT
  }
}

# Output the builder image URL so you can use it in your CodeBuild project definition
output "builder_image_url" {
  value = "${aws_ecr_repository.codebuild_builder.repository_url}:latest"
}