#!/bin/bash
# Script to download and vendor Helm charts for air-gapped installation.
# Run this from the repository root before running 'terraform apply'.

set -e

# Define the target directory within the terraform module
TARGET_DIR="commitlab-infra/charts"
echo "Vendoring charts into $TARGET_DIR"
mkdir -p "$TARGET_DIR"

# 1. ArgoCD (v6.7.11)
echo "--> Vendoring ArgoCD chart..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm pull argo/argo-cd --version 6.7.11 --untar -d "$TARGET_DIR"

# 2. Metrics Server (v3.12.1)
echo "--> Vendoring Metrics Server chart..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm pull metrics-server/metrics-server --version 3.12.1 --untar -d "$TARGET_DIR"

# 3. Kubernetes Dashboard (v6.0.8)
echo "--> Vendoring Kubernetes Dashboard chart..."
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ >/dev/null 2>&1 || true
helm pull kubernetes-dashboard/kubernetes-dashboard --version 6.0.8 --untar -d "$TARGET_DIR"

echo "--> Chart vendoring complete."