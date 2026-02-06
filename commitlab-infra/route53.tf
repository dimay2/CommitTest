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

# 2. Output the Zone ID (Needed for the script in Step 3)
output "hosted_zone_id" {
  description = "The ID of the Private Route53 Zone"
  value       = aws_route53_zone.private.zone_id
}