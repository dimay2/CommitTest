# AWS Lab 8 - EKS Services and Pipeline

## Table of Contents
1. [Solution Overview](#solution-overview)
2. [Accessing the Environment](#1-accessing-the-environment)
3. [How to Upgrade the Application](#2-how-to-upgrade-the-application)
4. [Troubleshooting & Maintenance](#3-troubleshooting--maintenance)

## Solution Overview
This project implements a secure, air-gapped Kubernetes environment on AWS EKS. It adheres to strict security requirements, ensuring no direct internet access for the cluster or the build pipeline.

### Key Features
*   **Strictly Private Networking:** The VPC has no Internet Gateway. All traffic remains within the AWS private network.
*   **EKS Fargate:** Serverless compute for Kubernetes pods.
*   **Private CI/CD:** AWS CodePipeline and CodeBuild operate entirely within private subnets.
*   **GitOps:** ArgoCD manages application synchronization.
*   **Internal Access:** Services are exposed via Internal Application Load Balancers (ALB) and Route53 Private DNS.

## 1. Accessing the Environment
Access to the environment is restricted to the **EC2 Windows Jumpbox**.

### Prerequisites
*   Connect to the Jumpbox using **AWS Systems Manager (Fleet Manager)** or RDP.
*   All URLs below must be accessed from the browser inside the Jumpbox.

### Service URLs
| Application | URL | Description |
| :--- | :--- | :--- |
| **Frontend Application** | `http://Lab-commit-task.commit.local` | The main user-facing application. |
| **ArgoCD UI** | `https://argocd.commit.local` | GitOps dashboard for managing deployments. |

> **Note:** For ArgoCD, accept the self-signed certificate warning in the browser (Advanced -> Proceed).

### ArgoCD Login
*   **Username:** `admin`
*   **Password:** Run the following command in PowerShell on the Jumpbox to retrieve the initial password:
    ```powershell
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($input))
    ```

## 2. How to Upgrade the Application
To deploy a new version of the application, follow this Git-based workflow:

1.  **Clone the Repository:**
    ```bash
    git clone https://git-codecommit.eu-north-1.amazonaws.com/v1/repos/commitlab-app-repo
    cd commitlab-app-repo
    ```

2.  **Modify the Code:**
    *   Make changes to the source code (e.g., `app/frontend/templates/index.html`).
    *   Or update the Helm chart configuration.

3.  **Push Changes:**
    ```bash
    git add .
    git commit -m "Feature: Updated frontend welcome message"
    git push origin master
    ```

4.  **Deployment Process:**
    *   **CodePipeline** detects the commit.
    *   **CodeBuild** compiles the application, builds Docker images, and pushes them to the private ECR.
    *   **ArgoCD** (or the Pipeline) detects the new artifacts and syncs the changes to the EKS cluster.

5.  **Verify:**
    *   Check the pipeline status in the AWS Console.
    *   Refresh the **Frontend Application** URL to see the update.

## 3. Troubleshooting & Maintenance

### DNS Resolution
If the `.local` domains are not resolving, the internal DNS records may need a refresh. Run the update script from the Jumpbox or CloudShell:

```bash
./scripts/update-dns.sh
```

### Cluster Access
To run `kubectl` commands manually:
```bash
aws eks update-kubeconfig --region eu-north-1 --name commitlab-cluster
kubectl get pods -A
```