# Create a Private Hosted Zone for the internal domain
resource "aws_route53_zone" "private" {
  name = "commit.local"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = {
    Environment = var.environment_tag
  }
}

# Execute the DNS update script whenever it changes
resource "null_resource" "update_dns_script" {
  triggers = {
    script_hash = filemd5("${path.module}/../scripts/update-dns.sh")
  }

  provisioner "local-exec" {
    command = "/bin/bash ${path.module}/../scripts/update-dns.sh"
    environment = {
      CLUSTER_NAME = var.cluster_name
      ZONE_ID      = aws_route53_zone.private.zone_id
      AWS_REGION   = var.aws_region
    }
  }
}