# AWS Lab 8 — EKS Services & Pipeline

This repository contains the Terraform infrastructure, Helm charts, and application code required to provision an AWS environment with an EKS cluster (Fargate), **Strictly Private Networking** (Air-Gapped), ArgoCD, Monitoring, and a sample Python web application backed by MySQL.

## Table of contents
- [Prerequisites & Cleanup](#prerequisites--cleanup)
- [Repository layout](#repository-layout)
- [Quick start](#quick-start)
- [Terraform backend (S3 + DynamoDB)](#terraform-backend-s3--dynamodb)
- [Build & push container images](#build--push-container-images)
- [Install AWS Load Balancer Controller](#install-aws-load-balancer-controller)
- [Deploy application (Helm)](#deploy-application-helm)
- [Configure Internal DNS (Crucial)](#configure-internal-dns-crucial)
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

* `commitlab-infra/` — Terraform for **Strictly Private** networking, EKS v1.30, ArgoCD, Monitoring, RDS, and Route53 Private Zone.
* `app/backend/` — Backend application and Dockerfile.
* `app/frontend/` — Frontend application and Dockerfile.
* `helm/` — Helm chart for the application deployment.
* `update-dns.sh` — **Bridge Script** to update Route53 in this air-gapped environment.

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

The Terraform output automatically provides the ARN of the self-signed certificate generated during infrastructure provisioning.

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

## Configure Internal DNS (Crucial)

Since this is an **Air-Gapped** environment (No Internet Gateway), the cluster cannot reach the public Route53 API to automatically create DNS records. You must run this "Bridge Script" from your management console (where you ran Terraform) to link the internal Load Balancer to the private domain.

**1. Create the `update-dns.sh` file (if not present):**

```bash
cat <<EOF > update-dns.sh
#!/bin/bash
# Route53 Air-Gap Bridge Script
HOSTED_ZONE_NAME="commit.local"
RECORD_NAME="Lab-commit-task.commit.local"
REGION="us-east-1"

echo "--> 1. Reading Terraform outputs..."
CLUSTER_NAME=\$(terraform -chdir=commitlab-infra output -raw cluster_name)
ZONE_ID=\$(terraform -chdir=commitlab-infra output -raw hosted_zone_id)

if [ -z "\$CLUSTER_NAME" ] || [ -z "\$ZONE_ID" ]; then
  echo "❌ Error: Terraform outputs missing."
  exit 1
fi

echo "--> 2. Fetching Internal ALB Hostname..."
ALB_DNS=\$(aws eks update-kubeconfig --region \$REGION --name \$CLUSTER_NAME >/dev/null && kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "\$ALB_DNS" ]; then
  echo "❌ Error: ALB Hostname not found. Is Helm deployed?"
  exit 1
fi
echo "    ALB: \$ALB_DNS"

echo "--> 3. Updating Route53 Private Record..."
CHANGE_BATCH=\$(cat <<EOT
{
  "Comment": "Air-Gap Update",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "\$RECORD_NAME",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "\$ALB_DNS"}]
      }
    }
  ]
}
EOT
)
aws route53 change-resource-record-sets --hosted-zone-id \$ZONE_ID --change-batch "\$CHANGE_BATCH"
echo "✅ Success! DNS Updated."
EOF

```

**2. Make it executable and run it:**

```bash
chmod +x update-dns.sh
./update-dns.sh

```

**3. Verification:**
Wait for the output: `✅ Success! DNS Updated.`
*If this step is skipped, the URL `https://Lab-commit-task.commit.local` will NOT resolve.*

## Verify deployment

1. **Connect to the Windows Jumpbox:**
Access the Windows instance via AWS Systems Manager (SSM). For RDP access through the private network, use SSM Port Forwarding:
```bash
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=commitlab-app-windows-jumpbox" --query "Reservations[0].Instances[0].InstanceId" --output text)

# Start RDP tunnel (Requires SSM Session Manager Plugin)
aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["3389"],"localPortNumber":["53389"]}'

```


2. Connect via RDP to `localhost:53389`.
3. **Verify Application Access (DNS Test):**
* Open Chrome on the Windows instance.
* Navigate to `https://Lab-commit-task.commit.local`.
* **Success Criteria:** The page loads with the app version string.
* **Note:** If you see "DNS_PROBE_FINISHED_NXDOMAIN", rerun the `update-dns.sh` script from your management console.
* Click the padlock icon to verify the certificate is issued by **"CommitLab DevOps"**.


4. **Verify Monitoring (Dashboard):**
* **Create Token:**
```bash
kubectl create token admin-user -n monitoring

```


* **Proxy Dashboard:**
```bash
kubectl port-forward svc/kubernetes-dashboard-kong-proxy -n monitoring 8443:443

```


* Open `https://localhost:8443` in your browser.
* Paste the token to log in. You should see CPU/Memory usage metrics for your pods (powered by Metrics Server).


5. **Verify ArgoCD Access:**
* **Retrieve Password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

```


* **Access UI:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

```


* Open `https://localhost:8080` in your browser.
* Login with user `admin` and the retrieved password.



## Notes & security

* **Private Isolation:** The environment contains no Internet Gateway or Public Subnets. Connectivity to AWS services is maintained via VPC Interface and Gateway Endpoints.
* **Access Control:** All administration is performed through the Windows Jumpbox via SSM; no SSH/RDP ports are open to the internet.
* **DNS Architecture:** A "Split-Plane" approach is used. Terraform manages the Route53 Zone, while the `update-dns.sh` script bridges the air-gap to update records from the management plane.