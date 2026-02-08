# AWS Lab 8 — EKS Services & Pipeline

This repository contains the Terraform infrastructure, Helm charts, and application code required to provision an AWS environment with an EKS cluster (Fargate), **Strictly Private Networking** (Air-Gapped), ArgoCD, Monitoring, and a sample Python web application backed by MySQL.

## Table of contents
- [Prerequisites & Tool Installation](#prerequisites--tool-installation)
- [Repository layout](#repository-layout)
- [Quick start](#quick-start)
- [Important: Private ECR image enforcement](#important-private-ecr-image-enforcement-for-air-gapped-eks)
- [Build & push container images](#build--push-container-images)
- [Mirror images for an air-gapped cluster](#mirror-images-for-an-air-gapped-cluster-private-ecr)
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

# 5. Install skopeo (for image mirroring to private ECR)
# Use Docker container for skopeo (works in CloudShell and EC2)
docker run --rm quay.io/skopeo/stable:latest inspect docker://docker.io/alpine:latest

# Create alias for easier usage
echo 'alias skopeo="docker run --rm -it quay.io/skopeo/stable:latest"' >> ~/.bashrc
source ~/.bashrc

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

* `commitlab-infra/` — Terraform for **Strictly Private** networking, EKS v1.30, AWS Load Balancer Controller, ArgoCD, Monitoring, RDS, and Route53 Private Zone.
* `app/backend/` — Backend application and Dockerfile.
* `app/frontend/` — Frontend application and Dockerfile.
* `helm/` — Helm chart defining the **Frontend**, **Backend**, and **ALB Ingress** resources.
* `commitlab-infra/charts/` — Vendored Helm charts for air-gapped installation.
* `scripts/` — Utility scripts including `mirror-images.sh` for mirroring container images to private ECR.
* `scripts/vendor-charts.sh` — Script to download Helm charts locally.
* `.github/mirror-images.txt` — Image manifest for the mirroring script.
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
The S3 bucket and DynamoDB table for the Terraform backend must also be configured in `commitlab-infra/backend.tf`.

```bash
export TF_VAR_db_password="YOUR_DB_PASSWORD"
export TF_VAR_environment_tag="dimatest"
export AWS_REGION="eu-north-1"
export TF_STATE_BUCKET="<your-unique-terraform-bucket>" # Must match 'bucket' in backend.tf
export TF_LOCK_TABLE="<your-terraform-lock-table>"   # Must match 'dynamodb_table' in backend.tf

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

### 3.5 Grant Terraform IAM permissions (required before `terraform apply`)

When Terraform creates some AWS resources (for example the `aws_codebuild_project`), the AWS API calls Terraform makes must be allowed by the IAM user or role whose credentials you use to run `terraform apply`. A common failure is an `InvalidInputException: Not authorized to perform DescribeSecurityGroups` error because `ec2:DescribeSecurityGroups` (and related describe actions) are missing.

Below are two ways to grant the minimum additional permissions: using the AWS Console (UI) or the AWS CLI. Replace `TERRAFORM_PRINCIPAL` with the IAM user name or role name/ARN that you use to run Terraform.

- Minimal policy JSON (allow these EC2 describe actions):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:DescribeNetworkInterfaces"
      ],
      "Resource": "*"
    }
  ]
}
```

Console steps (attach to a user or role):

1. Open the AWS Management Console → IAM → Policies → Create policy.
2. Choose the JSON tab and paste the minimal policy above, then click Next.
3. Give the policy a name like `Terraform-Ec2Describe-ReadOnly` and create it.
4. Go to IAM → Users (or Roles) → select the user/role you use for Terraform → "Add permissions" → Attach policies and attach `Terraform-Ec2Describe-ReadOnly`.

AWS CLI steps (create policy and attach to a user):

```bash
# 1) Create the policy from the JSON file (local file: terraform-ec2-describe.json)
aws iam create-policy \
  --policy-name Terraform-Ec2Describe-ReadOnly \
  --policy-document file://terraform-ec2-describe.json

# 2) Attach the policy to an IAM user (example: terraform-user)
aws iam attach-user-policy \
  --user-name TERRAFORM_PRINCIPAL \
  --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/Terraform-Ec2Describe-ReadOnly

# OR attach to a role:
aws iam attach-role-policy \
  --role-name TERRAFORM_PRINCIPAL \
  --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/Terraform-Ec2Describe-ReadOnly
```

Notes:
- If you already have an IAM policy for Terraform, you can simply add `ec2:DescribeSecurityGroups` (and the related `Describe*` actions shown above) to that existing policy instead of creating a new one.
- For short-term testing, you can run `terraform apply` using credentials with broader permissions (for example an administrator) to confirm the error is permission-related, then scope down to the minimal policy above.
- If your `aws_codebuild_project` uses `vpc_config` (as this repo does), AWS validates the referenced subnets and security groups at create time — Terraform will need the `ec2:Describe*` permissions to successfully create the CodeBuild project.


### 3.6 Vendor Helm Charts (Required)

The Terraform configuration relies on local Helm charts located in `commitlab-infra/charts/`. You must run the vendoring script to download these charts before provisioning infrastructure.

```bash
chmod +x scripts/vendor-charts.sh
./scripts/vendor-charts.sh
```

4. **Initialize and Apply Terraform:**
Navigate to the infrastructure directory and provision the resources.
**Note:** This step can take 15-20 minutes.

```bash
cd commitlab-infra
terraform init

# Review the plan before applying
terraform plan -out=tfplan

# Apply the planned changes
terraform apply tfplan

```

### Important: Private ECR image enforcement for air-gapped EKS

The Terraform configuration is pre-configured to pull all Helm chart images from your **private ECR** (not public Internet registries). This is enforced by:

- `argocd.tf` → ArgoCD components pull from private ECR
- `monitoring.tf` → Metrics Server and Kubernetes Dashboard pull from private ECR
- `alb-controller.tf` → AWS Load Balancer Controller pulls from private ECR
- All pod images default to: `ACCOUNT_ID.dkr.ecr.AWS_REGION.amazonaws.com/image-name:tag`

**Before running `terraform apply` (or immediately after):**

1. Mirror all required images to your private ECR using the script provided:
```bash
cd ..
export AWS_REGION=eu-north-1
chmod +x scripts/mirror-images.sh
./scripts/mirror-images.sh .github/mirror-images.txt
```

2. If images are not mirrored to ECR before Helm releases deploy, pods will fail with `ImagePullBackOff`.

3. See the **[Mirror images for an air-gapped cluster](#mirror-images-for-an-air-gapped-cluster-private-ecr)** section below for detailed mirroring instructions.

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

## Build & push application container images

ECR repositories for your application (`lab-backend` and `lab-frontend`) are created automatically by Terraform (see `commitlab-infra/ecr.tf`). To build and push your application images to ECR:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-eu-north-1}

# Login to ECR (repositories already created by Terraform)
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push Backend
cd app/backend
docker build -t lab-backend:latest .
docker tag lab-backend:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-backend:latest
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-backend:latest

# Build and push Frontend
cd ../frontend
docker build -t lab-frontend:latest .
docker tag lab-frontend:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-frontend:latest
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/lab-frontend:latest

# Return to root
cd ../../
```

**Note:** If you receive "repository not found" errors, verify that `terraform apply` completed successfully in `commitlab-infra/` and that ECR repositories were created.

### Mirror images for an air-gapped cluster (private ECR)

In a strictly private / air-gapped environment your EKS Fargate pods cannot pull images from public registries unless you provide a private image registry accessible from the VPC. The recommended pattern for this lab is:

- **ECR repositories are created automatically by Terraform** (see `commitlab-infra/ecr.tf`), so you do not need to manually create them. When you run `terraform apply`, all required ECR repos are provisioned.
- On a management host with Internet access (your admin workstation or CloudShell with Internet), pull upstream images (Helm chart images), re-tag them to your private ECR repos, and push them.
- Ensure the EKS VPC has VPC endpoints for ECR and S3 (Terraform creates these in `vpc.tf`), so Fargate can access ECR without Internet.
- Update Helm `values` (or use `--set`) to point charts at your private ECR image URIs.

### Step 1: Retrieve ECR repository URIs from Terraform outputs

After `terraform apply` completes, run:

```bash
cd commitlab-infra
terraform output ecr_repository_urls
```

This will print all ECR repo URIs in your account. Example output:
```
{
  "argocd_server" = "123456789012.dkr.ecr.eu-north-1.amazonaws.com/argocd-server"
  "argocd_repo_server" = "123456789012.dkr.ecr.eu-north-1.amazonaws.com/argocd-repo-server"
  ...
}
```

Save this output or reference it in your mirroring scripts below.

### Step 2: Mirror images from upstream into your private ECR (production approach with skopeo)

A production-ready mirroring script is provided: `scripts/mirror-images.sh`

This script uses **skopeo** (industry best practice) for efficient, direct registry-to-registry copying with:
- Automatic retry logic (3 attempts with backoff)
- Comprehensive logging to `mirror-logs/`
- Support for image manifests across architectures
- No local disk staging of images

#### How to mirror all images

**1. Review and customize the image manifest:**

The image list is maintained in `.github/mirror-images.txt` (one image per line):

```
quay.io/argoproj/argocd:v2.9.8:argocd-server
registry.k8s.io/metrics-server/metrics-server:v0.6.4:metrics-server
# ... more images
```

Edit this file to:
- Update image versions if using different Helm chart versions
- Add/remove images based on your deployment needs

**2. Run the mirror script:**

```bash
cd CommitTest
export AWS_REGION=eu-north-1
chmod +x scripts/mirror-images.sh
./scripts/mirror-images.sh .github/mirror-images.txt
```

**3. Monitor progress:**

The script logs all operations to `mirror-logs/mirror-<timestamp>.log`:

```bash
# Watch logs in real-time (in another terminal)
tail -f mirror-logs/mirror-*.log
```

#### Script features

- **Automatic retry**: Failed copies retry up to 3 times with 5-second backoff
- **Colored output**: Easy-to-read status messages (success, error, warning, info)
- **Validation**: Checks prerequisites (skopeo, aws CLI), validates manifest format
- **Logging**: Timestamped logs for all operations, audit trail
- **Summary**: Final report with success/failure counts

Example output:
```
2025-02-07 14:23:45 [INFO] ========== Image Mirror Script Started ==========
2025-02-07 14:23:45 [INFO] Account ID: 123456789012
2025-02-07 14:23:45 [INFO] Region: eu-north-1
2025-02-07 14:23:45 [INFO] Manifest: .github/mirror-images.txt
...
2025-02-07 14:24:12 [SUCCESS] Successfully mirrored: quay.io/argoproj/argocd:v2.10.6 -> 123456789012.dkr.ecr.eu-north-1.amazonaws.com/argocd-server:v2.10.6
...
====== MIRRORING SUMMARY ======
Total images: 12
Successful: 12
Log file: mirror-logs/mirror-20250207_142345.log
```

#### Advanced usage

**Mirror only specific images:**

Create a custom manifest and pass it to the script:

```bash
# Create custom list (e.g., only ArgoCD images)
cat > custom-images.txt <<EOF
quay.io/argoproj/argocd:v2.10.6:argocd-server
quay.io/argoproj/argocd:v2.10.6:argocd-repo-server
EOF

./scripts/mirror-images.sh custom-images.txt
```

**Change retry behavior:**

Edit `scripts/mirror-images.sh` and modify:
```bash
MAX_RETRIES=3       # Number of retry attempts
RETRY_DELAY=5       # Seconds between retries
```

**Integration with CI/CD:**

The script is designed to be called from CI/CD pipelines or scheduled jobs:

```bash
./scripts/mirror-images.sh .github/mirror-images.txt && echo "Mirror succeeded" || echo "Mirror failed"
```

### Step 3: Find upstream image versions

Before mirroring, you need to know which images and versions are used by each Helm chart. Run:

```bash
# View chart values and images
helm show values argo/argo-cd --version 6.7.11
helm show values kubernetes-sigs/metrics-server --version 3.12.1
helm show values bitnami/redis --version 18.0.0
# etc.

# Or download and inspect the chart
helm pull argo/argo-cd --untar
grep -r "image:" ./argo-cd/ | grep repository
```

Document the images you find and adapt the `mirror-images.sh` script accordingly.

### Step 4: Ensure VPC endpoints exist for private ECR pulls

When you run `terraform apply`, the following endpoints are created automatically:
- S3 gateway endpoint: `com.amazonaws.$AWS_REGION.s3`
- ECR API interface endpoint: `com.amazonaws.$AWS_REGION.ecr.api`
- ECR Docker interface endpoint: `com.amazonaws.$AWS_REGION.ecr.dkr`
- STS interface endpoint: `com.amazonaws.$AWS_REGION.sts` (optional, for token exchange)

Verify they exist (optional):

```bash
aws ec2 describe-vpc-endpoints --region $AWS_REGION --query 'VpcEndpoints[?ServiceName==`com.amazonaws.'$AWS_REGION'.ecr.api`]'
aws ec2 describe-vpc-endpoints --region $AWS_REGION --query 'VpcEndpoints[?ServiceName==`com.amazonaws.'$AWS_REGION'.s3`]'
```

### Step 5: Update Helm values to reference private ECR images

Once images are pushed to ECR, update your Helm installation commands to use the private ECR URIs. Examples:

#### ArgoCD (update argocd.tf or use CLI overrides):

```bash
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set global.image.repository=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com \
  --set server.image.repository=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/argocd-server \
  --set server.image.tag=v2.9.8 \
  --set repoServer.image.repository=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/argocd-repo-server \
  --set repoServer.image.tag=v2.9.8 \
  # ... (other overrides)
```

#### Metrics Server:

```bash
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace monitoring --create-namespace \
  --set image.repository=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/metrics-server \
  --set image.tag=v0.6.4
```

Or update `argocd.tf` and `monitoring.tf` Helm values blocks to reference your ECR URIs:

```hcl
values = [
  <<-EOT
  server:
    image:
      repository: ${var.ecr_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/argocd-server
      tag: v2.9.8
  EOT
]
```

### Step 6: Optional — Create imagePullSecrets if needed

For most setups with proper IAM/IRSA roles, imagePullSecrets are not required. But if pods need explicit Docker credentials:

```bash
aws ecr get-login-password --region $AWS_REGION | kubectl create secret docker-registry ecr-regcred \
  --docker-server=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com \
  --docker-username=AWS --docker-password-stdin --namespace argocd
```

### Notes and best practices

- **Keep image tags consistent**: Preserve the original tag (e.g., `v2.9.8`) when mirroring so you know which upstream version you have.
- **Use skopeo for large image sets**: Faster and avoids large temporary disk usage.
- **Verify endpoint connectivity**: Ensure the security group on ECR endpoints allows inbound HTTPS (port 443) from Fargate pod security groups.
- **Check ECR repository policy**: By default, Terraform repositories allow pull/push from the same AWS account; if using cross-account setups, adjust the policy.
- **Test pulls from the cluster**: Once deployed, run a test pod and verify it can pull from your ECR:
  ```bash
  kubectl run --image=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/argocd-server:v2.9.8 test-pull --rm -it -- sh
  ```

---

## Configure CoreDNS for Fargate

By default, CoreDNS is tainted to run only on EC2 nodes. Since this cluster uses **Fargate**, you must remove the compute-type annotation to allow CoreDNS pods to run on Fargate:

```bash
# Remove the EC2-only compute-type annotation from CoreDNS
kubectl patch deployment coredns \
  -n kube-system \
  -p '{"spec":{"template":{"metadata":{"annotations":{"eks.amazonaws.com/compute-type":null}}}}}'

# Restart the CoreDNS deployment to apply the changes
kubectl rollout restart deployment coredns -n kube-system

# Verify CoreDNS pods are running on Fargate
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
```

**Expected output:** CoreDNS pods should transition to `Running` state and show Fargate as the compute provider.

---

## Deploy application (Helm)

Deploy the application using the local Helm chart. **This chart provisions the full application stack required by the lab:**

1.  **Frontend Pods**: The web interface (Hello Lab-commit).
2.  **Backend Pods**: The Python API connecting to the RDS database.
3.  **ALB Ingress**: An AWS Application Load Balancer that routes traffic to the frontend and handles SSL termination.

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
RECORD_NAME="lab-commit-task.commit.local"
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
* Navigate to `https://lab-commit-task.commit.local`.
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