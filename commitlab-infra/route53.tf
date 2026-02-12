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

# Create a CNAME record pointing argocd.commit.local to the ALB
resource "aws_route53_record" "argocd" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "argocd.commit.local"
  type    = "CNAME"
  ttl     = 300
  records = [kubernetes_ingress_v1.argocd.status.0.load_balancer.0.ingress.0.hostname]
}