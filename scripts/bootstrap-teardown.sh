#!/usr/bin/env bash
# One-command bootstrap teardown (recover KMS, empty bucket, destroy, cleanup).
#
# Usage:
#   export TF_PROJECT_NAME=my-project TF_ENVIRONMENT=dev
#   export AWS_REGION=us-east-1 AWS_ACCOUNT_ID=123456789012
#   export BOOTSTRAP_KMS_KEY_ARN=arn:aws:kms:REGION:ACCOUNT:key/KEY-ID   # if key Disabled/PendingDeletion
#   ./scripts/bootstrap-teardown.sh
#
# Optional: recover KMS only (no destroy):
#   ./scripts/bootstrap-teardown.sh recover

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${repo_root}/.github/scripts/terraform-common.sh"

mode="${1:-teardown}"

: "${TF_PROJECT_NAME:?Set TF_PROJECT_NAME}"
: "${TF_ENVIRONMENT:?Set TF_ENVIRONMENT}"
: "${AWS_REGION:?Set AWS_REGION}"
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"

case "${mode}" in
  recover)
    bootstrap_recover_kms "${BOOTSTRAP_KMS_KEY_ARN:-}"
    echo "KMS recovered. Run: bootstrap_init global/bootstrap"
    ;;
  teardown | destroy)
    bootstrap_finish_teardown global/bootstrap
    ;;
  *)
    echo "Usage: $0 [recover|teardown]" >&2
    exit 1
    ;;
esac
