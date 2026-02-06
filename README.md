# AWS Lab 8 — EKS Services & Pipeline

This repository contains Terraform, Helm, and application code used to provision an AWS environment with an EKS cluster (Fargate), private networking, and a sample Python web application backed by MySQL. The README below provides a concise, GitHub-friendly guide to prerequisites, deployment steps, and verification.

## Table of contents
- [Prerequisites](#prerequisites)
- [Repository layout](#repository-layout)
- [Quick start](#quick-start)
- [Terraform backend (S3 + DynamoDB)](#terraform-backend-s3--dynamodb)
- [Build & push container images](#build--push-container-images)
- [Install AWS Load Balancer Controller](#install-aws-load-balancer-controller)
- [Deploy application (Helm)](#deploy-application-helm)
- [Verify deployment](#verify-deployment)
- [Notes & security](#notes--security)

---

## Prerequisites
- Git
- Terraform (v1.0+)
- Helm 3
- AWS CLI v2
- kubectl
- Docker (for building images)
- An AWS account with permissions to create IAM, ECR, S3, DynamoDB, EKS, and ACM resources

Install examples (CloudShell / macOS / Linux):

```bash
# Terraform
terraform -version

# Helm
helm version

# AWS CLI
aws --version

# kubectl
kubectl version --client

# Docker
docker --version
```

## Repository layout

- `commitlab-infra/` — Terraform for networking, EKS, RDS, etc.
- `app/backend/` — Backend app and Dockerfile
- `app/frontend/` — Frontend app and Dockerfile
- `helm/` — Helm chart for the application

## Quick start

1. Configure required environment variables (example):

```bash
export TF_VAR_db_password="YOUR_DB_PASSWORD"
export AWS_REGION=us-east-1
export TF_STATE_BUCKET="<your-unique-terraform-bucket>"
export TF_LOCK_TABLE="<your-terraform-lock-table>"
```

2. Create Terraform backend (S3 bucket + DynamoDB table) — see next section.

3. Initialize and apply Terraform (from `commitlab-infra`):

```bash
cd commitlab-infra
terraform init \ 
  -backend-config="bucket=$TF_STATE_BUCKET" \ 
  -backend-config="region=$AWS_REGION" \ 
  -backend-config="dynamodb_table=$TF_LOCK_TABLE"
terraform plan -out=tfplan
terraform apply tfplan
```

4. Configure kubectl for the created EKS cluster:

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
export REGION=$(terraform output -raw region)
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
```

## Terraform backend (S3 + DynamoDB)

Create a versioned S3 bucket and a DynamoDB table for state locking:

```bash
aws s3 mb s3://$TF_STATE_BUCKET --region $AWS_REGION
aws s3api put-bucket-versioning --bucket $TF_STATE_BUCKET --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name $TF_LOCK_TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
```

## Build & push container images

Create ECR repos and push images (replace variables accordingly):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr create-repository --repository-name lab-backend || true
aws ecr create-repository --repository-name lab-frontend || true

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Backend
cd app/backend
docker build -t lab-backend .
docker tag lab-backend:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/lab-backend:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/lab-backend:latest

# Frontend
cd ../frontend
docker build -t lab-frontend .
docker tag lab-frontend:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/lab-frontend:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/lab-frontend:latest
```

## Install AWS Load Balancer Controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

## Deploy application (Helm)

Create Kubernetes secrets and install the Helm chart:

```bash
# Example: create secret for DB connection
kubectl create secret generic backend-secrets \
  --from-literal=db-host=$RDS_ENDPOINT \
  --from-literal=db-password=$TF_VAR_db_password

cd helm
helm install lab-app . \
  --set backend.image=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/lab-backend:latest \
  --set frontend.image=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/lab-frontend:latest
```

If you need TLS via ACM, import or request a certificate and pass its ARN to the chart (see chart values).

## Verify deployment

Get the ingress/ALB hostname:

```bash
kubectl get ingress -o wide
ALB_HOSTNAME=$(kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB Hostname: $ALB_HOSTNAME"
```

Visit `https://<ALB_HOSTNAME>` (or configure local hosts for a self-signed cert if using a jumpbox). Expected page shows frontend and backend status.

## Notes & security

- Do not commit secrets or plaintext passwords to the repo. Use `TF_VAR_` variables, SSM Parameter Store, or Secrets Manager.
- Use least-privilege IAM roles for CI/CD and deploy bots.
- If the remote repository already has commits, fetch and reconcile histories before pushing.

---

If you want, I can also:

- Draft a sample `main.tf` for the infra (I can create it under `commitlab-infra/`).
- Run the local `git` commands to add and commit this change.

File updated: `README.md`
