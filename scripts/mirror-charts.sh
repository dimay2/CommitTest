#!/bin/bash
# Mirror Helm Charts to OCI for Air-Gapped EKS
# Usage: ./scripts/mirror-charts.sh

set -e

AWS_REGION="${AWS_REGION:-eu-north-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# 1. Login to ECR (Helm Registry)
echo "Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | helm registry login --username AWS --password-stdin $ECR_URL

# 2. Mirror Kubernetes Dashboard Chart
# We pull the official chart (6.0.8) which installs App v2.7.0
# We repackage it as version 2.7.0 to match Terraform and avoid collision with image tag v2.7.0
CHART_NAME="kubernetes-dashboard"
UPSTREAM_VERSION="6.0.8"
TARGET_VERSION="2.7.0"
REPO_URL="https://kubernetes.github.io/dashboard/"

echo "Pulling $CHART_NAME:$UPSTREAM_VERSION from $REPO_URL..."
helm repo add kubernetes-dashboard $REPO_URL
helm repo update
helm pull kubernetes-dashboard/$CHART_NAME --version $UPSTREAM_VERSION --untar

echo "Repackaging as version $TARGET_VERSION..."
sed -i "s/^version: .*/version: $TARGET_VERSION/" $CHART_NAME/Chart.yaml
helm package $CHART_NAME

echo "Pushing $CHART_NAME-$TARGET_VERSION.tgz to oci://$ECR_URL/"
helm push $CHART_NAME-$TARGET_VERSION.tgz oci://$ECR_URL/

rm -rf $CHART_NAME $CHART_NAME-$TARGET_VERSION.tgz
echo "Success! Chart mirrored."