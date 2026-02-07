#!/bin/bash
################################################################################
# Production Image Mirroring Script for Air-Gapped EKS
# Uses skopeo for efficient registry-to-registry image copying with retry logic
#
# Usage: ./mirror-images.sh [image-manifest-file]
# Example: ./mirror-images.sh .github/mirror-images.txt
#
# Image manifest format (one per line):
#   source-registry/image:tag:target-ecr-repo-name
#
# Example entries:
#   quay.io/argoproj/argocd:v2.9.8:argocd-server
#   registry.k8s.io/metrics-server/metrics-server:v0.6.4:metrics-server
################################################################################

# NO set -e to avoid pipe/subshell issues with file redirection in CloudShell

# Configuration
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="${AWS_REGION:-eu-north-1}"
IMAGES_FILE="${1:-.github/mirror-images.txt}"
LOG_DIR="./mirror-logs"
MIRROR_LOG="$LOG_DIR/mirror-$(date +%Y%m%d_%H%M%S).log"
MAX_RETRIES=3
RETRY_DELAY=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create log directory
mkdir -p "$LOG_DIR"

# Logging function
log() {
  local level="$1"
  shift
  local message="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${timestamp} [${level}] ${message}" | tee -a "$MIRROR_LOG"
}

log_success() {
  log "${GREEN}SUCCESS${NC}" "$@"
}

log_error() {
  log "${RED}ERROR${NC}" "$@"
}

log_warning() {
  log "${YELLOW}WARNING${NC}" "$@"
}

log_info() {
  log "${BLUE}INFO${NC}" "$@"
}

# Check prerequisites
check_requirements() {
  log_info "Checking prerequisites..."
  
  if ! command -v docker &> /dev/null; then
    log_error "Docker not found. Required for running skopeo container."
    return 1
  fi
  
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found"
    return 1
  fi
  
  if [ ! -f "$IMAGES_FILE" ]; then
    log_error "Image manifest file not found: $IMAGES_FILE"
    return 1
  fi
  
  log_success "All prerequisites met"
  return 0
}

# Validate image manifest format
validate_manifest() {
  log_info "Validating image manifest: $IMAGES_FILE"
  
  local valid_lines=0
  local line_num=0
  
  # Simple, bulletproof method: no pipes, no subshells
  while IFS= read -r line || [ -n "$line" ]; do
    ((line_num++))
    
    # Skip empty lines
    if [ -z "$line" ]; then
      continue
    fi
    
    # Skip comment lines starting with #
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    
    # Count colons using awk (no pipes)
    local colon_count=$(echo "$line" | awk -F: '{print NF-1}')
    
    if [ "$colon_count" -lt 2 ]; then
      log_error "Line $line_num: Invalid format (found $colon_count colons, need 2+)"
      log_error "  Got: $line"
      log_error "  Expected: registry/image:tag:target-repo-name"
      return 1
    fi
    
    ((valid_lines++))
  done < "$IMAGES_FILE"
  
  if [ "$valid_lines" -eq 0 ]; then
    log_warning "No images found in manifest (only comments/blank lines)"
    return 1
  fi
  
  log_success "Manifest validation passed ($valid_lines images found)"
  return 0
}

# Get ECR authentication token
get_ecr_credentials() {
  log_info "Authenticating with ECR..."
  SKOPEO_ECR_PASSWORD=$(aws ecr get-login-password --region "$AWS_REGION" 2>/dev/null)
  
  if [ -z "$SKOPEO_ECR_PASSWORD" ]; then
    log_error "Failed to get ECR authentication token"
    return 1
  fi
  
  export SKOPEO_ECR_PASSWORD
  log_success "ECR authentication successful"
  return 0
}

# Retry function for skopeo copy (via Docker container - no -it flags for scripts)
retry_copy() {
  local source="$1"
  local target="$2"
  local attempt=1
  
  while [ $attempt -le $MAX_RETRIES ]; do
    log_info "Copying [$attempt/$MAX_RETRIES]: $source -> $target"
    
    # Call skopeo via Docker container (no -it flags for non-interactive scripts)
    if docker run --rm \
      quay.io/skopeo/stable:latest copy \
      --dest-creds "AWS:$SKOPEO_ECR_PASSWORD" \
      "docker://$source" \
      "docker://$target" 2>> "$MIRROR_LOG"; then
      log_success "Successfully mirrored: $source -> $target"
      return 0
    fi
    
    if [ $attempt -lt $MAX_RETRIES ]; then
      log_warning "Attempt $attempt failed. Retrying in ${RETRY_DELAY}s..."
      sleep $RETRY_DELAY
    fi
    ((attempt++))
  done
  
  log_error "Failed after $MAX_RETRIES attempts: $source"
  return 1
}

# Main mirroring logic
mirror_images() {
  log_info "Starting image mirroring process"
  
  local total_images=0
  local successful=0
  local failed=0
  
  # Count total images
  total_images=$(grep -v '^#' "$IMAGES_FILE" | grep -v '^$' | wc -l)
  log_info "Found $total_images images to mirror"
  
  # Simple, bulletproof file reading - no pipes, no subshells
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines
    if [ -z "$line" ]; then
      continue
    fi
    
    # Skip comment lines
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    
    # Parse using rev and cut: split on last two colons
    # Example: quay.io/argoproj/argocd:v2.9.8:argocd-server
    local source=$(echo "$line" | rev | cut -d: -f3- | rev)
    local tag=$(echo "$line" | rev | cut -d: -f2 | rev)
    local target_repo=$(echo "$line" | rev | cut -d: -f1 | rev)
    
    # Validate parsing
    if [ -z "$source" ] || [ -z "$tag" ] || [ -z "$target_repo" ]; then
      log_error "Failed to parse: $line"
      ((failed++))
      continue
    fi
    
    local target="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$target_repo:$tag"
    
    log_info "Processing: $source:$tag -> ECR:$target_repo:$tag"
    
    if retry_copy "$source:$tag" "$target"; then
      ((successful++))
    else
      ((failed++))
    fi
  done < "$IMAGES_FILE"
  
  # Summary
  echo ""
  log_info "====== MIRRORING SUMMARY ======"
  log_info "Total images: $total_images"
  log_success "Successful: $successful"
  if [ $failed -gt 0 ]; then
    log_error "Failed: $failed"
  fi
  log_info "Log file: $MIRROR_LOG"
  echo ""
  
  if [ $failed -gt 0 ]; then
    log_error "Mirror operation completed with $failed failures"
    return 1
  else
    log_success "All images mirrored successfully!"
    return 0
  fi
}

# Main execution
main() {
  log_info "========== Image Mirror Script Started =========="
  log_info "Account ID: $ACCOUNT_ID"
  log_info "Region: $AWS_REGION"
  log_info "Manifest: $IMAGES_FILE"
  log_info "Max Retries: $MAX_RETRIES"
  echo ""
  
  check_requirements || exit 1
  validate_manifest || exit 1
  get_ecr_credentials || exit 1
  mirror_images
}

# Run main function
main "$@"
