#!/bin/bash
# ------------------------------------------------------------------
# Route53 Air-Gap Updater
# Purpose: Fetches the Internal ALB address and updates the Private Route53 Zone
# ------------------------------------------------------------------

REGION="${AWS_REGION:-eu-north-1}"

echo "--> 1. Reading Infrastructure Details..."

# Check if variables are set (from Terraform), otherwise try to fetch from Terraform outputs
if [ -z "$CLUSTER_NAME" ]; then
  echo "    CLUSTER_NAME not set, attempting to fetch from Terraform output..."
  CLUSTER_NAME=$(terraform -chdir=/home/cloudshell-user/CommitTest/commitlab-infra output -raw cluster_name 2>/dev/null)
fi

if [ -z "$ZONE_ID" ]; then
  echo "    ZONE_ID not set, attempting to fetch from Terraform output..."
  ZONE_ID=$(terraform -chdir=/home/cloudshell-user/CommitTest/commitlab-infra output -raw hosted_zone_id 2>/dev/null)
fi

if [ -z "$CLUSTER_NAME" ] || [ -z "$ZONE_ID" ]; then
  echo "Error: Cluster Name or Zone ID could not be determined."
  exit 1
fi

echo "    Cluster: $CLUSTER_NAME"
echo "    Zone ID: $ZONE_ID"

echo "--> 2. Updating Kubeconfig..."
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME >/dev/null

update_record() {
  local ingress_name=$1
  local namespace=$2
  local record_name=$3

  echo "--> Processing $record_name (Ingress: $ingress_name in $namespace)..."

  # Fetch ALB Hostname
  ALB_DNS=$(kubectl get ingress "$ingress_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

  if [ -z "$ALB_DNS" ]; then
    echo "    Warning: ALB Hostname not found for $ingress_name. Skipping update."
    return
  fi

  echo "    ALB Address: $ALB_DNS"

  # Construct JSON payload
  CHANGE_BATCH=$(cat <<EOF
{
  "Comment": "Air-Gap Update for $record_name",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$record_name",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "$ALB_DNS"
          }
        ]
      }
    }
  ]
}
EOF
)

  # Update Route53
  aws route53 change-resource-record-sets \
    --hosted-zone-id $ZONE_ID \
    --change-batch "$CHANGE_BATCH"
    
  echo "    Success! Updated $record_name"
}

# Update Frontend DNS
update_record "app-ingress" "default" "lab-commit-task.commit.local"

# Update ArgoCD DNS
update_record "argocd-server" "argocd" "argocd.commit.local"

echo "--> DNS Update Process Completed."