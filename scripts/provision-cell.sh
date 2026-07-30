#!/usr/bin/env bash
# provision-cell.sh — Provisions a new customer cell via Terraform
# Usage: ./scripts/provision-cell.sh <CUSTOMER_ID> <AWS_REGION> <TIER>
# Tiers: standard | enterprise | regulated
#
# All output is tee'd to a timestamped audit log for SOC 2 compliance.

set -euo pipefail

# ---------------------------------------------------------------------------
# Audit Logging Setup
# ---------------------------------------------------------------------------
SCRIPT_NAME="provision-cell.sh"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
AUDIT_LOG="${LOG_DIR}/provision-${TIMESTAMP}.log"

# Tee all stdout/stderr to audit log file
exec > >(tee -a "$AUDIT_LOG") 2>&1

log() {
  local level="$1"
  shift
  local message="$*"
  # Structured JSON audit log entry
  printf '{"timestamp":"%s","level":"%s","script":"%s","customer_id":"%s","message":"%s"}\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$level" "$SCRIPT_NAME" "${CUSTOMER_ID:-UNKNOWN}" "$message"
}

# ---------------------------------------------------------------------------
# Argument Validation
# ---------------------------------------------------------------------------
if [[ $# -lt 3 ]]; then
  log "ERROR" "Missing required arguments"
  echo ""
  echo "Usage: $0 <CUSTOMER_ID> <AWS_REGION> <TIER>"
  echo "  CUSTOMER_ID : Unique customer identifier (e.g., acme-corp)"
  echo "  AWS_REGION  : AWS region (e.g., eu-central-1)"
  echo "  TIER        : Deployment tier: standard | enterprise | regulated"
  echo ""
  exit 1
fi

CUSTOMER_ID="$1"
AWS_REGION="$2"
TIER="$3"

# Validate CUSTOMER_ID format (lowercase alphanumeric and hyphens only)
if ! [[ "$CUSTOMER_ID" =~ ^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$ ]]; then
  log "ERROR" "Invalid CUSTOMER_ID: '${CUSTOMER_ID}'. Must be lowercase alphanumeric with hyphens, 3-32 chars."
  exit 1
fi

# Validate AWS_REGION format
if ! [[ "$AWS_REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
  log "ERROR" "Invalid AWS_REGION: '${AWS_REGION}'. Example: eu-central-1"
  exit 1
fi

# Validate TIER
case "$TIER" in
  standard|enterprise|regulated)
    ;;
  *)
    log "ERROR" "Invalid TIER: '${TIER}'. Must be one of: standard, enterprise, regulated"
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Pre-flight Checks
# ---------------------------------------------------------------------------
log "INFO" "Starting provisioning for customer_id=${CUSTOMER_ID} region=${AWS_REGION} tier=${TIER}"

# Ensure required CLI tools are available
for cmd in terraform aws helm; do
  if ! command -v "$cmd" &>/dev/null; then
    log "ERROR" "Required tool not found: ${cmd}"
    exit 1
  fi
done

log "INFO" "Pre-flight checks passed"

# Verify AWS credentials are available and functional
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)
if [[ -z "$CALLER_ARN" ]]; then
  log "ERROR" "AWS credentials not configured or invalid. Please authenticate first."
  exit 1
fi
log "INFO" "AWS credentials validated caller_arn=${CALLER_ARN}"

# ---------------------------------------------------------------------------
# Terraform Workspace Setup
# ---------------------------------------------------------------------------
CELL_NAME="${CUSTOMER_ID}-cell"
TF_DIR="./terraform"
TF_WORKSPACE="$CELL_NAME"
TF_STATE_KEY="${CELL_NAME}/terraform.tfstate"

log "INFO" "Initialising Terraform workspace=${TF_WORKSPACE}"

terraform -chdir="$TF_DIR" init -reconfigure \
  -backend-config="bucket=acme-terraform-state" \
  -backend-config="key=${TF_STATE_KEY}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="encrypt=true" \
  -backend-config="dynamodb_table=acme-terraform-locks"

log "INFO" "Terraform init complete"

# Create or select Terraform workspace
if terraform -chdir="$TF_DIR" workspace list | grep -q "^[* ]*${TF_WORKSPACE}$"; then
  terraform -chdir="$TF_DIR" workspace select "$TF_WORKSPACE"
  log "INFO" "Selected existing Terraform workspace=${TF_WORKSPACE}"
else
  terraform -chdir="$TF_DIR" workspace new "$TF_WORKSPACE"
  log "INFO" "Created new Terraform workspace=${TF_WORKSPACE}"
fi

# ---------------------------------------------------------------------------
# Terraform Plan
# ---------------------------------------------------------------------------
log "INFO" "Running Terraform plan"

terraform -chdir="$TF_DIR" plan \
  -var="environment=${CUSTOMER_ID}" \
  -var="aws_region=${AWS_REGION}" \
  -out="${TF_WORKSPACE}.tfplan"

log "INFO" "Terraform plan complete. Plan saved to ${TF_WORKSPACE}.tfplan"

# ---------------------------------------------------------------------------
# Terraform Apply
# ---------------------------------------------------------------------------
log "INFO" "Applying Terraform plan for workspace=${TF_WORKSPACE}"

terraform -chdir="$TF_DIR" apply -auto-approve "${TF_WORKSPACE}.tfplan"

log "INFO" "Terraform apply complete"

# ---------------------------------------------------------------------------
# Capture Outputs for Helm / downstream use
# ---------------------------------------------------------------------------
log "INFO" "Capturing Terraform outputs"
VPC_ID=$(terraform -chdir="$TF_DIR" output -raw vpc_id)
RDS_ENDPOINT=$(terraform -chdir="$TF_DIR" output -raw rds_endpoint)
S3_BUCKET_ARN=$(terraform -chdir="$TF_DIR" output -raw s3_bucket_arn)

log "INFO" "Provisioning complete vpc_id=${VPC_ID} rds_endpoint=${RDS_ENDPOINT} s3_arn=${S3_BUCKET_ARN}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "====================================================================="
echo " Cell provisioned successfully!"
echo " Customer : ${CUSTOMER_ID}"
echo " Region   : ${AWS_REGION}"
echo " Tier     : ${TIER}"
echo " Audit log: ${AUDIT_LOG}"
echo "====================================================================="
log "INFO" "Provisioning script finished successfully"
