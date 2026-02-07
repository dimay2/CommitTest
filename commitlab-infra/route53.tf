# 1. Create the Private Hosted Zone
resource "aws_route53_zone" "private" {
  name = var.hosted_zone_name # e.g., "commit.local"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  # Allows terraform destroy to work even if the zone has records
  force_destroy = true 

  tags = {
    Name = "${var.app_name}-private-zone"
  }
}