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

  depends_on = [null_resource.mirror_images]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      ECR_URL="${aws_ecr_repository.codebuild_builder.repository_url}"
      REGION="${data.aws_region.current.name}"
      REGISTRY_URL=$(echo "$ECR_URL" | cut -d'/' -f1)
      
      # Login to ECR
      aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL
      
      # Build and Push
      cd ../builder
      echo "=== BUILDING BUILDER IMAGE: $${ECR_URL}:latest ==="
      docker build --build-arg REGISTRY_URL=$REGISTRY_URL -t $${ECR_URL}:latest .
      echo "=== PUSHING BUILDER IMAGE: $${ECR_URL}:latest ==="
      docker push $${ECR_URL}:latest
    EOT
  }
}

# Output the builder image URL so you can use it in your CodeBuild project definition
output "builder_image_url" {
  value = "${aws_ecr_repository.codebuild_builder.repository_url}:latest"
}

# 3. Mirror images to private ECR
# This ensures all images defined in mirror-images.txt are present in the private ECR
resource "null_resource" "mirror_images" {
  triggers = {
    manifest_hash = filemd5("${path.module}/../.github/mirror-images.txt")
    script_hash   = filemd5("${path.module}/../scripts/mirror-images.sh")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      export AWS_REGION="${data.aws_region.current.name}"
      chmod +x ${path.module}/../scripts/mirror-images.sh
      ${path.module}/../scripts/mirror-images.sh ${path.module}/../.github/mirror-images.txt
    EOT
  }
}