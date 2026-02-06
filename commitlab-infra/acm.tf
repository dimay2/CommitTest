# 1. Generate a secure private key
resource "tls_private_key" "app_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# 2. Generate a Self-Signed Certificate
# Common Name matches the required domain: Lab-commit-task.commit.local
resource "tls_self_signed_cert" "app_cert" {
  private_key_pem = tls_private_key.app_key.private_key_pem

  subject {
    common_name  = "Lab-commit-task.${var.hosted_zone_name}"
    organization = "CommitLab DevOps"
  }

  validity_period_hours = 8760 # 1 Year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# 3. Import the Certificate to AWS ACM
resource "aws_acm_certificate" "imported_cert" {
  private_key      = tls_private_key.app_key.private_key_pem
  certificate_body = tls_self_signed_cert.app_cert.cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.app_name}-self-signed"
  }
}