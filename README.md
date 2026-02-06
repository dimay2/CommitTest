This update modifies the **Deploy application (Helm)** section to automatically retrieve the certificate ARN using Terraform, and adds a specific **SSL Verification** step to the **Verify deployment** section.

**File Path:** `dimay2/committest/CommitTest-aabff9bfb5c8a1d6ba18613c5575771356417b0c/README.md`

```text
# AWS Lab 8 — EKS Services & Pipeline

This repository contains the Terraform infrastructure, Helm charts, and application code required to provision an AWS environment with an EKS cluster (Fargate), strictly private networking, and a sample Python web application backed by MySQL.

## Table of contents
- [Prerequisites & Cleanup](#prerequisites--cleanup)
- [Repository layout](#repository-layout)
- [Quick start](#quick-start)
- [Terraform backend (S3 + DynamoDB)](#terraform-backend-s3--dynamodb)
- [Build & push container images](#build--push-container-images)
- [Install AWS Load Balancer Controller](#install-aws-load-balancer-controller)
- [Deploy application (Helm)](#deploy-application-helm)
- [Verify deployment](#verify-deployment)
- [Notes & security](#notes--security)

---

## Prerequisites & Cleanup

### Tools Required
- Git, Terraform (v1.5+), Helm 3, AWS CLI v2, kubectl, Docker.

### ⚠️ Requirement: Delete Default VPC
Per the lab requirements, the Default VPC must be deleted before provisioning the new environment. Use the following script to identify and remove it:

```bash
# Identify the Default VPC ID
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)

if [ "$DEFAULT_VPC_ID" != "None" ]; then
  echo "Deleting Default VPC: $DEFAULT_VPC_ID"
  
  # 1. Delete associated Subnets
  SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$DEFAULT_VPC_ID --query "Subnets[].SubnetId" --output text)
  for subnet in $SUBNETS; do
    aws ec2 delete-subnet --subnet-id $subnet
    echo "Deleted subnet $subnet"
  done

  # 2. Detach and delete Internet Gateway
  IGW=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$DEFAULT_VPC_ID --query "InternetGateways[].InternetGatewayId" --output text)
  if [ "$IGW" != "None" ] && [ -n "$IGW" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $DEFAULT_VPC_ID
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW
    echo "Deleted IGW $IGW"
  fi

  # 3. Delete the VPC
  aws ec2 delete-vpc --vpc-id $DEFAULT_VPC_ID
  echo "Default VPC successfully deleted."
else
  echo "No Default VPC found."
fi

```

## Repository layout

* `commitlab-infra/` — Terraform for **Private-Only** networking, EKS v1.30, RDS, and VPC Endpoints.
* `app/backend/` — Backend application and Dockerfile.
* `app/frontend/` — Frontend application and Dockerfile.
* `helm/` — Helm chart for the application deployment.

## Quick start

1. Configure required environment variables:

```bash
export TF_VAR_db_password="YOUR_DB_PASSWORD"
export AWS_REGION="us-east-1"
export TF_STATE_BUCKET="<your-unique-terraform-bucket>"
export TF_LOCK_TABLE="<your-terraform-lock-table>"

```

2. Initialize and apply Terraform (from `commitlab-infra`):

```bash
cd commitlab-infra
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="dynamodb_table=$TF_LOCK_TABLE"
terraform apply -auto-approve

```

3. Configure kubectl for the EKS cluster:

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

```

## Terraform backend (S3 + DynamoDB)

Ensure a versioned S3 bucket and DynamoDB table exist for state management:

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

Create ECR repositories and push the application images. In this private environment, the cluster pulls images via ECR VPC Interface Endpoints.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr create-repository --repository-name lab-backend || true
aws ecr create-repository --repository-name lab-frontend || true

aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Backend
cd app/backend
docker build -t lab-backend .
docker tag lab-backend:latest $ACCOUNT_ID.dkr.ecr.$AWS_[REGION.amazonaws.com/lab-backend:latest](https://REGION.amazonaws.com/lab-backend:latest)
docker push $ACCOUNT_ID.dkr.ecr.$AWS_[REGION.amazonaws.com/lab-backend:latest](https://REGION.amazonaws.com/lab-backend:latest)

# Frontend
cd ../frontend
docker build -t lab-frontend .
docker tag lab-frontend:latest $ACCOUNT_ID.dkr.ecr.$AWS_[REGION.amazonaws.com/lab-frontend:latest](https://REGION.amazonaws.com/lab-frontend:latest)
docker push $ACCOUNT_ID.dkr.ecr.$AWS_[REGION.amazonaws.com/lab-frontend:latest](https://REGION.amazonaws.com/lab-frontend:latest)

```

## Install AWS Load Balancer Controller

```bash
helm repo add eks [https://aws.github.io/eks-charts](https://aws.github.io/eks-charts)
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

```

## Deploy application (Helm)

The Terraform output now automatically provides the ARN of the self-signed certificate generated during infrastructure provisioning.

```bash
# Create Kubernetes secret for DB credentials
kubectl create secret generic backend-secrets \
  --from-literal=db-host=$(terraform output -raw rds_endpoint) \
  --from-literal=db-password=$TF_VAR_db_password

cd helm
helm install lab-app . \
  --set backend.image=$ACCOUNT_ID.dkr.ecr.$AWS_[REGION.amazonaws.com/lab-backend:latest](https://REGION.amazonaws.com/lab-backend:latest) \
  --set frontend.image=$ACCOUNT_ID.dkr.ecr.$AWS_[REGION.amazonaws.com/lab-frontend:latest](https://REGION.amazonaws.com/lab-frontend:latest) \
  --set ingress.certificateArn=$(terraform output -raw acm_certificate_arn)

```

## Verify deployment

1. **Connect to the Windows Jumpbox:**
Access the Windows instance via AWS Systems Manager (SSM). For RDP access through the private network, use SSM Port Forwarding:
```bash
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=commitlab-app-windows-jumpbox" --query "Reservations[0].Instances[0].InstanceId" --output text)

# Start RDP tunnel (Requires SSM Session Manager Plugin)
aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["3389"],"localPortNumber":["53389"]}'

```


2. Connect via RDP to `localhost:53389`.
3. **Verify Application Access:** Open a browser on the Windows instance and navigate to `https://Lab-commit-task.commit.local`.
4. **Verify SSL Certificate:** Click the padlock icon in the browser address bar. View the certificate details and confirm it was issued by **"CommitLab DevOps"** (the self-signed authority created by Terraform).

## Notes & security

* **Private Isolation:** The environment contains no Internet Gateway or Public Subnets. Connectivity to AWS services is maintained via VPC Interface and Gateway Endpoints.
* **Access Control:** All administration is performed through the Windows Jumpbox via SSM; no SSH/RDP ports are open to the internet.

```

```