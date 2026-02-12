# Create a private key for the self-signed certificate
resource "tls_private_key" "argocd" {
  algorithm = "RSA"
}

# Create a self-signed certificate
resource "tls_self_signed_cert" "argocd" {
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