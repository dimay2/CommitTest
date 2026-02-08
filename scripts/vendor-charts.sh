#!/bin/bash
# Script to download and vendor Helm charts for air-gapped installation.
# Run this from the repository root before running 'terraform apply'.

set -e

# Define the target directory within the terraform module
TARGET_DIR="commitlab-infra/charts"
echo "Vendoring charts into $TARGET_DIR"
mkdir -p "$TARGET_DIR"

# 1. ArgoCD (v6.7.11)
# Clean up previous extraction if it exists
rm -rf "$TARGET_DIR/argo-cd"
echo "--> Vendoring ArgoCD chart..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm pull argo/argo-cd --version 6.7.11 --untar -d "$TARGET_DIR"

# 2. Metrics Server (v3.12.1)
# Clean up previous extraction if it exists
rm -rf "$TARGET_DIR/metrics-server"
echo "--> Vendoring Metrics Server chart..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm pull metrics-server/metrics-server --version 3.12.1 --untar -d "$TARGET_DIR"

# 3. Kubernetes Dashboard (v6.0.8)
# Clean up previous extraction if it exists
rm -rf "$TARGET_DIR/kubernetes-dashboard"
echo "--> Vendoring Kubernetes Dashboard chart..."
# Official repo index is frequently unavailable (404). Pulling directly from the backing gh-pages branch.
helm pull https://raw.githubusercontent.com/kubernetes/dashboard/gh-pages/kubernetes-dashboard-6.0.8.tgz --untar -d "$TARGET_DIR"

echo "--> Chart vendoring complete."