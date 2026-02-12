# Create a private key for the self-signed certificate
resource "tls_private_key" "argocd" {
  algorithm = "RSA"
}

# Create a self-signed certificate
resource "tls_self_signed_cert" "argocd" {
  key_algorithm   = "RSA"
  private_key_pem = tls_private_key.argocd.private_key_pem

  subject {
    common_name  = "argocd.commit.local"
    organization = "Commit Lab"
  }

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Import the certificate into AWS ACM
resource "aws_acm_certificate" "argocd" {
  private_key      = tls_private_key.argocd.private_key_pem
  certificate_body = tls_self_signed_cert.argocd.cert_pem
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
      "alb.ingress.kubernetes.io/certificate-arn"  = aws_acm_certificate.argocd.arn
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