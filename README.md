I have cleaned up the formatting and corrected the syntax errors (particularly the broken ECR URLs) from your notes to create a professional `README.md` file.

```markdown
# AWS Lab 8 - EKS Services & Pipeline

This project deploys a secure AWS environment featuring an EKS Fargate cluster, private networking, and a Python-based web application with a MySQL backend. Infrastructure is provisioned via Terraform, and deployment is managed via Helm.

## Table of Contents
* [Install Tools & Setup](#01-install-tools-and-setup-directories)
* [Secure Environment Variables](#02-set-secure-environment-variables)
* [Terraform Backend Setup](#03-manual-creation-of-terraform-backend-s3--dynamodb-in-aws)
* [Infrastructure Deployment](#04-create-main-infra-with-terraform)
* [Environment Configuration](#05-environment-configuration)
* [Build & Push Images](#06-build-and-push-images)
* [Install Load Balancer Controller](#07-install-load-balancer-controller)
* [Deploy Application](#08-deploy-application)
* [Verification](#09-verification)

---

## 01: Install Tools and setup directories
Run the following commands in AWS CloudShell to install Terraform, Helm 3, and create necessary directories.

```bash
# Install Terraform
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo [https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo](https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo)
sudo yum -y install terraform

# Install Helm 3
curl [https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3](https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3) | bash

# Verify installation
terraform -version
helm version

# Create dir for Terraform files
mkdir -p ~/commitlab-infra

# Create dir for app
mkdir -p ~/app/backend ~/app/frontend

# Create dir for Helm
mkdir -p ~/helm/templates

```

## 02: Set Secure Environment Variables

Set the database password securely in the session memory.

```bash
# Set the DB Password as an environment variable
# Terraform will automatically read this because of the TF_VAR_ prefix
export TF_VAR_db_password="SuperSecretPass123!Secure"

```

## 03: Manual creation of Terraform backend (S3 + DynamoDB) in AWS

Create the S3 bucket for state storage and DynamoDB table for state locking.

```bash
# 1. Set your unique bucket name (must be globally unique)
export TF_STATE_BUCKET="lab8-terraform-state"
export TF_LOCK_TABLE="lab8-terraform-locks"
export AWS_REGION="us-east-1"  # Change if needed

# 2. Create S3 Bucket
aws s3 mb s3://$TF_STATE_BUCKET --region $AWS_REGION
aws s3api put-bucket-versioning --bucket $TF_STATE_BUCKET --versioning-configuration Status=Enabled

# 3. Create DynamoDB Table for State Locking
aws dynamodb create-table \
    --table-name $TF_LOCK_TABLE \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

# 4. Variables verification
echo "Your State Bucket Name is: $TF_STATE_BUCKET"
echo "Lock Table:   $TF_LOCK_TABLE"

```

## 04: Create main Infra with Terraform

Initialize and apply the Terraform configuration.

```bash
cd ~/commitlab-infra

# Ensure DB Password variable is set
if [ -z "$TF_VAR_db_password" ]; then
  echo "ERROR: TF_VAR_db_password is not set. Run 'export TF_VAR_db_password=...'"
  exit 1
fi

terraform init \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="dynamodb_table=$TF_LOCK_TABLE"

terraform plan -out=tfplan
terraform apply tfplan

```

## 05: Environment configuration

Retrieve outputs from Terraform and configure access to the EKS cluster.

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
export REGION=$(terraform output -raw region)
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

```

## 06: Build and Push Images

Authenticate with ECR and push the application images.

```bash
aws ecr create-repository --repository-name lab-backend
aws ecr create-repository --repository-name lab-frontend

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Backend
cd ~/app/backend
docker build -t lab-backend .
docker tag lab-backend:latest $ACCOUNT_ID.dkr.ecr.$[REGION.amazonaws.com/lab-backend:latest](https://REGION.amazonaws.com/lab-backend:latest)
docker push $ACCOUNT_ID.dkr.ecr.$[REGION.amazonaws.com/lab-backend:latest](https://REGION.amazonaws.com/lab-backend:latest)

# Frontend
cd ~/app/frontend
docker build -t lab-frontend .
docker tag lab-frontend:latest $ACCOUNT_ID.dkr.ecr.$[REGION.amazonaws.com/lab-frontend:latest](https://REGION.amazonaws.com/lab-frontend:latest)
docker push $ACCOUNT_ID.dkr.ecr.$[REGION.amazonaws.com/lab-frontend:latest](https://REGION.amazonaws.com/lab-frontend:latest)

```

## 07: Install Load Balancer Controller

Deploy the AWS Load Balancer Controller to the cluster using Helm.

```bash
helm repo add eks [https://aws.github.io/eks-charts](https://aws.github.io/eks-charts)
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

```

## 08: Deploy Application

Generate certificates, create secrets, and deploy the application chart.

```bash
# 1. Generate Cert
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=Lab-commit-task.commit.local"
CERT_ARN=$(aws acm import-certificate --certificate fileb://cert.pem --private-key fileb://key.pem --query CertificateArn --output text)

# 2. Create Kubernetes Secret
kubectl create secret generic backend-secrets \
  --from-literal=db-host=$RDS_ENDPOINT \
  --from-literal=db-password=$TF_VAR_db_password

# 3. Deploy Helm
cd ~/helm
helm install lab-app . \
    --set ingress.certificateArn=$CERT_ARN \
    --set backend.image=$ACCOUNT_ID.dkr.ecr.$[REGION.amazonaws.com/lab-backend:latest](https://REGION.amazonaws.com/lab-backend:latest) \
    --set frontend.image=$ACCOUNT_ID.dkr.ecr.$[REGION.amazonaws.com/lab-frontend:latest](https://REGION.amazonaws.com/lab-frontend:latest)

```

## 09: Verification

### 09.1: Get ALB URL

Run the following to retrieve the Application Load Balancer DNS name:

```bash
# Obtain LB URL
export ALB_HOSTNAME=$(kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB Hostname: $ALB_HOSTNAME"

```

### 09.2: Reset Windows Password via SSM

1. Go to **AWS Console** > **Systems Manager** > **Session Manager**.
2. Select the instance named `commitlab-app-windows-jumpbox` and click **Start session**.
3. In the PowerShell CLI that opens, run:
```powershell
net user Administrator "MyStrongPassword123!"

```


4. Close the session.

### 09.3: Access via Fleet Manager (RDP)

1. Go to **AWS Console** > **Systems Manager** > **Fleet Manager**.
2. Select `commitlab-app-windows-jumpbox`.
3. Click **Node Actions** > **Connect** > **Connect with Remote Desktop**.
4. Select **User credentials**:
* **Username**: Administrator
* **Password**: (The password you set in step 09.2)


5. Click **Connect**.

### 09.4: DNS Config & Test (Inside RDP Session)

1. Open **Notepad** as Administrator and edit `C:\Windows\System32\drivers\etc\hosts`.
2. Add the following line (replace `<ALB_IP>` with the IP resolved from the hostname in Step 09.1):
```text
<ALB_IP>  Lab-commit-task.commit.local

```


3. Open a browser and navigate to: `https://Lab-commit-task.commit.local`.
4. Accept the self-signed certificate warning.

**Expected Result**: You should see a page displaying:

* `Frontend Version: v1.0.0`
* `Backend Says: Hello Lab-commit 10`

```

Would you like me to help you draft the `main.tf` file for the infrastructure deployment in step 04?

```