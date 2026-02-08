#!/bin/bash
# ------------------------------------------------------------------
# Route53 Air-Gap Updater
# Purpose: Fetches the Internal ALB address and updates the Private Route53 Zone
# ------------------------------------------------------------------

# Configuration
RECORD_NAME="lab-commit-task.commit.local"
REGION="eu-north-1"

echo "--> 1. Reading Infrastructure Details..."
# We fetch the Cluster Name and Zone ID from Terraform outputs
CLUSTER_NAME=$(terraform -chdir=commitlab-infra output -raw cluster_name)
ZONE_ID=$(terraform -chdir=commitlab-infra output -raw hosted_zone_id)

if [ -z "$CLUSTER_NAME" ] || [ -z "$ZONE_ID" ]; then
  echo "Error: Terraform outputs are missing. Did you run 'terraform apply'?"
  exit 1
fi

echo "--> 2. Fetching Internal ALB Hostname..."
# We ask Kubernetes (via the public API endpoint) what the ALB address is
ALB_DNS=$(aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME >/dev/null && kubectl get ingress app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$ALB_DNS" ]; then
  echo "Error: ALB Hostname not found. Is the Helm chart deployed?"
  exit 1
fi

echo "    ALB Address: $ALB_DNS"

echo "--> 3. Updating Route53 Private Record..."
# We construct the JSON payload to update the record
CHANGE_BATCH=$(cat <<EOF
{
  "Comment": "Air-Gap Update",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$RECORD_NAME",
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

# We call the Route53 API (Public) from our Management Station
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch "$CHANGE_BATCH"

echo "Success! The record $RECORD_NAME now points to your Internal ALB."