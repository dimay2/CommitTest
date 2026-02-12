# Fetch the ACM certificate for the domain (e.g., *.commit.local)
data "aws_acm_certificate" "wildcard" {
  domain      = "*.commit.local"
  most_recent = true
  statuses    = ["ISSUED"]
}

# Create an Internal ALB Ingress for ArgoCD
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internal"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTPS"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ "HTTPS" : 443 }])
      "alb.ingress.kubernetes.io/certificate-arn"  = data.aws_acm_certificate.wildcard.arn
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      "alb.ingress.kubernetes.io/group.name"       = "argocd-internal"
    }
  }

  spec {
    rule {
      host = "argocd.commit.local"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 443
              }
            }
          }
        }
      }
    }
  }
}