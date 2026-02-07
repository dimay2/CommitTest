# AWS Lab 8 — EKS Services & Pipeline

This repository contains the Terraform infrastructure, Helm charts, and application code required to provision an AWS environment with an EKS cluster (Fargate), **Strictly Private Networking** (Air-Gapped), ArgoCD, Monitoring, and a sample Python web application backed by MySQL.

## Table of contents
- [Prerequisites & Tool Installation](#prerequisites--tool-installation)
- [Repository layout](#repository-layout)
- [Quick start](#quick-start)
- [Build & push container images](#build--push-container-images)
- [Install AWS Load Balancer Controller](#install-aws-load-balancer-controller)
- [Deploy application (Helm)](#deploy-application-helm)
- [Configure Internal DNS (Crucial)](#configure-internal-dns-crucial)
- [CI/CD Pipeline (Triggering from GitHub Code)](#cicd-pipeline-triggering-from-github-code)
- [Verify deployment](#verify-deployment)
- [Notes & security](#notes--security)

---

## Prerequisites & Tool Installation

### 1. Install Required Tools
If you are running this from a fresh AWS CloudShell or Amazon Linux 2023 instance, run the following commands to install the necessary tools (Git, Terraform, Docker, Helm, Kubectl).

```bash
# Update System
sudo yum update -y

# 1. Install Git & Docker
sudo yum install -y git docker
sudo service docker start
sudo usermod -a -G docker ec2-user
# Note: You may need to logout and login again for docker group permissions to take effect.

# 2. Install Terraform
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum install -y terraform

# 3. Install kubectl (v1.30)
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.0/2024-05-12/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/

# 4. Install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

```

### 2. Requirement: Delete Default VPC

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
* `buildspec.yml` — Instructions for AWS CodeBuild to build and deploy the app.

## Quick start

1. **Clone the Repository:**
Download the project files from GitHub to your local AWS CLI environment.

```bash
git clone https://github.com/dimay2/CommitTest.git
cd CommitTest

```

2. **Configure Environment Variables:**
Set the required variables for Terraform and AWS. All AWS resources will be tagged with `Environment=dimatest` via Terraform's default_tags.

```bash
export TF_VAR_db_password="YOUR_DB_PASSWORD"
export TF_VAR_environment_tag="dimatest"
export AWS_REGION="eu-north-1"
export TF_STATE_BUCKET="<your-unique-terraform-bucket>"
export TF_LOCK_TABLE="<your-terraform-lock-table>"

```

3. **Create Backend Resources (S3 + DynamoDB):**
Create the S3 bucket and DynamoDB table **before** initializing Terraform.

```bash
aws s3 mb s3://$TF_STATE_BUCKET --region $AWS_REGION
aws s3api put-bucket-versioning --bucket $TF_STATE_BUCKET --versioning-configuration Status=Enabled
aws s3api put-bucket-tagging --bucket $TF_STATE_BUCKET --tagging 'TagSet=[{Key=Environment,Value='$TF_VAR_environment_tag'},{Key=Project,Value=CommitLab}]'

aws dynamodb create-table \
  --table-name $TF_LOCK_TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --tags Key=Environment,Value=$TF_VAR_environment_tag Key=Project,Value=CommitLab

```

4. **Initialize and Apply Terraform:**
Navigate to the infrastructure directory and provision the resources.
**Note:** This step can take 15-20 minutes.

```bash
cd commitlab-infra
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="dynamodb_table=$TF_LOCK_TABLE"
terraform apply -auto-approve

```

5. **Configure kubectl:**
Connect your CLI to the newly created EKS cluster.

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

```

### Resource Tagging

All AWS resources created by Terraform are automatically tagged with:
- **Project**: CommitLab
- **ManagedBy**: Terraform  
- **Environment**: dimatest (configured via `TF_VAR_environment_tag`)

Manual AWS CLI commands include the `dimatest` tag to maintain consistency. To modify the tag value, update `TF_VAR_environment_tag` environment variable before running Terraform.

## Build & push container images

Create ECR repositories and push the application images manually (for the initial deployment).

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr create-repository --repository-name lab-backend --tags key=Environment,value=$TF_VAR_environment_tag || true
aws ecr create-repository --repository-name lab-frontend --tags key=Environment,value=$TF_VAR_environment_tag || true

aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Backend
cd ../app/backend
docker build -t lab-backend .
docker tag lab-backend:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-backend:latest
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-backend:latest

# Frontend
cd ../frontend
docker build -t lab-frontend .
docker tag lab-frontend:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-frontend:latest
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-frontend:latest

# Return to root for next steps
cd ../../

```

## Install AWS Load Balancer Controller

We need to install the controller and ensure it uses the IAM Role created by Terraform (`commitlab-cluster-alb-controller`).

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# 1. Get the IAM Role ARN created by Terraform
ALB_ROLE_ARN=$(aws iam get-role --role-name commitlab-cluster-alb-controller --query Role.Arn --output text)
echo "Attaching Service Account to Role: $ALB_ROLE_ARN"

# 2. Install Controller with Service Account creation enabled
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ALB_ROLE_ARN

```

## Deploy application (Helm)

Deploy the application using the local Helm chart.

```bash
# Create Kubernetes secret for DB credentials
kubectl create secret generic backend-secrets \
  --from-literal=db-host=$(cd commitlab-infra && terraform output -raw rds_endpoint) \
  --from-literal=db-password=$TF_VAR_db_password

cd helm
helm install lab-app . \
  --set backend.image=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-backend:latest \
  --set frontend.image=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-frontend:latest \
  --set ingress.certificateArn=$(cd ../commitlab-infra && terraform output -raw acm_certificate_arn)

# Return to root
cd ..

```

## Configure Internal DNS (Crucial)

Since this is an **Air-Gapped** environment, run this bridge script from your management console to update the Route53 Private Zone.

**1. Create the update-dns.sh file (if not present):**

```bash
cat <<EOF > update-dns.sh
#!/bin/bash
# Route53 Air-Gap Bridge Script
HOSTED_ZONE_NAME="commit.local"
RECORD_NAME="Lab-commit-task.commit.local"
REGION="eu-north-1"

echo "--> 1. Reading Terraform outputs..."
CLUSTER_NAME=\$(terraform -chdir=commitlab-infra output -raw cluster_name)
ZONE_ID=\$(terraform -chdir=commitlab-infra output -raw hosted_zone_id)

if [ -z "\$CLUSTER_NAME" ] || [ -z "\$ZONE_ID" ]; then
  echo "[ERROR] Terraform outputs missing."
  exit 1
fi

echo "--> 2. Fetching Internal ALB Hostname..."
ALB_DNS=\$(aws eks update-kubeconfig --region \$REGION --name \$CLUSTER_NAME >/dev/null && kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "\$ALB_DNS" ]; then
  echo "[ERROR] ALB Hostname not found. Is Helm deployed?"
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
echo "[SUCCESS] DNS Updated."
EOF

```

**2. Make it executable and run it:**

```bash
chmod +x update-dns.sh
./update-dns.sh

```

**3. Verification:**
Wait for the output: `[SUCCESS] DNS Updated.`

## CI/CD Pipeline (Triggering from GitHub Code)

Terraform provisions a **CodePipeline** that listens to a private **CodeCommit** repository. To trigger the pipeline using the code you just cloned from GitHub:

1. **Retrieve the Private Repo URL:**
Get the HTTP clone URL of the AWS CodeCommit repository created by Terraform.

```bash
REPO_URL=$(aws codecommit get-repository --repository-name lab-app-repo --region $AWS_REGION --query 'repositoryMetadata.cloneUrlHttp' --output text)
echo "Target Repo: $REPO_URL"

```

2. **Configure Git Credentials for AWS:**
Configure your local git client to allow pushing to AWS CodeCommit.

```bash
git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true

```

3. **Push GitHub Code to AWS CodeCommit:**
Add the AWS repo as a new remote called `codecommit` and push the `main` branch.

```bash
# Add the private AWS repo as a remote
git remote add codecommit $REPO_URL

# Push the code you cloned from GitHub to the private AWS repo
git push codecommit main

```

4. **Verify Pipeline Execution:**

* Go to **AWS Console > CodePipeline**.
* Open `lab-app-pipeline`.
* You will see the pipeline triggering automatically from the push.
* **CodeBuild** will build a new image, push it to ECR, and run `helm upgrade` on the private cluster.

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
* **Note:** If you see "DNS_PROBE_FINISHED_NXDOMAIN", rerun the `update-dns.sh` script.

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