resource "aws_iam_role" "ssm_role" {
  name = "${var.app_name}-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "${var.app_name}-ssm-profile"
  role = aws_iam_role.ssm_role.name
}

# Use the most recent official Windows Server 2022 AMI for the region instead
# of a hardcoded AMI id which can be missing or invalid per-region.
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

resource "aws_instance" "windows_jumpbox" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = "t3.medium"
  subnet_id              = module.vpc.private_subnets[0]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  tags = { Name = "${var.app_name}-windows-jumpbox" }
}