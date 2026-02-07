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

set -euo pipefail

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
  log "$(printf '%b' "${GREEN}SUCCESS${NC}")" "$@"
}

log_error() {
  log "$(printf '%b' "${RED}ERROR${NC}")" "$@"
}

log_warning() {
  log "$(printf '%b' "${YELLOW}WARNING${NC}")" "$@"
}

log_info() {
  log "$(printf '%b' "${BLUE}INFO${NC}")" "$@"
}

# Check prerequisites
check_requirements() {
  log_info "Checking prerequisites..."
  
  if skopeo --version &> /dev/null; then
    log_error "skopeo not found. Install it:"
    echo "  macOS: brew install skopeo"
    echo "  Ubuntu/Debian: sudo apt-get install skopeo"
    echo "  Amazon Linux 2: sudo yum install skopeo"
    exit 1
  fi
  
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found"
    exit 1
  fi
  
  if [ ! -f "$IMAGES_FILE" ]; then
    log_error "Image manifest file not found: $IMAGES_FILE"
    exit 1
  fi
  
  log_success "All prerequisites met"
}

# Validate image manifest format
validate_manifest() {
  log_info "Validating image manifest: $IMAGES_FILE"
  if [ ! -f "$IMAGES_FILE" ]; then
    log_error "Manifest file not found: $IMAGES_FILE"
    exit 1
  fi
  
  local line_num=0
  local valid_lines=0
  
  while read -r line; do
    ((line_num++))
    
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^# ]]; then
      continue
    fi
    
    # Count colons - must have at least 2 (source:tag:repo)
    local colon_count=$(echo "$line" | grep -o ':' | wc -l || echo 0)
    
    if [ "$colon_count" -lt 2 ]; then
      log_error "Invalid format on line $line_num: $line"
      log_error "Expected format: registry/image:tag:target-repo-name (at least 2 colons)"
      log_error "Example: quay.io/argoproj/argocd:v2.9.8:argocd-server"
      exit 1
    fi
    
    ((valid_lines++))
  done < "$IMAGES_FILE"
  
  if [ "$valid_lines" -eq 0 ]; then
    log_warning "No images found in manifest (only comments/blank lines)"
  else
    log_success "Manifest validation passed ($valid_lines images found)"
  fi
}

# Get ECR authentication token
get_ecr_credentials() {
  log_info "Authenticating with ECR..."
  if ! export SKOPEO_ECR_PASSWORD=$(aws ecr get-login-password --region "$AWS_REGION" 2>/dev/null); then
    log_error "Failed to get ECR authentication token"
    exit 1
  fi
  log_success "ECR authentication successful"
}

# Retry function for skopeo copy
retry_copy() {
  local source="$1"
  local target="$2"
  local attempt=1
  
  while [ $attempt -le $MAX_RETRIES ]; do
    log_info "Copying [$attempt/$MAX_RETRIES]: $source -> $target"
    
    if skopeo copy \
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
  
  # Count total images (excluding comments and empty lines)
  total_images=$(grep -v '^#' "$IMAGES_FILE" | grep -v '^$' | wc -l)
  log_info "Found $total_images images to mirror"
  
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    
    # Parse: split on LAST two colons only (to handle registry URLs like quay.io/image:tag:repo)
    local target_repo="${line##*:}"          # Everything after last colon
    local temp="${line%:*}"                  # Everything except last colon
    local tag="${temp##*:}"                  # Last colon segment of temp
    local source="${temp%:*}"                # Everything except last colon of temp
    
    # Validate parsing
    if [[ -z "$source" || -z "$tag" || -z "$target_repo" ]]; then
      log_error "Failed to parse line: $line"
      ((failed++))
      continue
    fi
    
    local target="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$target_repo:$tag"
    
    log_info "Processing: $source:$tag -> $target_repo"
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
    log_error "Mirror operation completed with $failed failures. See log for details."
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
  
  check_requirements
  validate_manifest
  get_ecr_credentials
  mirror_images
}

# Run main function
main "$@"
