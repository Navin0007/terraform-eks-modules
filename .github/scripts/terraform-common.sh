#!/usr/bin/env bash
# Shared helpers for Terraform in GitHub Actions and local use.
set -euo pipefail

repo_root() {
  printf '%s\n' "${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
}

# Resolve a repo-relative path (safe when the workflow uses working-directory).
repo_path() {
  local path="${1:?}"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "$(repo_root)/${path}"
  fi
}

bootstrap_dir_abs() {
  repo_path "${1:-global/bootstrap}"
}

# Resolve environments/dev to an absolute path (safe after pushd into dev).
resolve_dev_dir() {
  local dev_dir="${1:-environments/dev}"
  if [[ "${dev_dir}" = /* ]]; then
    printf '%s\n' "${dev_dir}"
  else
    printf '%s\n' "$(repo_root)/${dev_dir}"
  fi
}

tf_common_vars() {
  : "${TF_PROJECT_NAME:?Set TF_PROJECT_NAME}"
  : "${TF_ENVIRONMENT:?Set TF_ENVIRONMENT}"
  : "${AWS_REGION:?Set AWS_REGION}"
  : "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"

  export TF_VAR_project_name="${TF_PROJECT_NAME}"
  export TF_VAR_environment="${TF_ENVIRONMENT}"
  export TF_VAR_region="${AWS_REGION}"
  export TF_VAR_aws_account_id="${AWS_ACCOUNT_ID}"
}

tf_var_args() {
  tf_common_vars
  printf '%s\n' \
    "-var=project_name=${TF_VAR_project_name}" \
    "-var=environment=${TF_VAR_environment}" \
    "-var=region=${TF_VAR_region}" \
    "-var=aws_account_id=${TF_VAR_aws_account_id}"
}

tf_dev_extra_var_args() {
  tf_export_dev_vars
  printf '%s\n' \
    "-var=state_kms_key_arn=${TF_VAR_state_kms_key_arn}" \
    "-var=state_bucket_name=${TF_VAR_state_bucket_name}" \
    "-var=state_kms_key_id=${TF_VAR_state_kms_key_id}" \
    "-var=dynamodb_table_name=${TF_VAR_dynamodb_table_name}"
}

# Export dev root-module variables for terraform import/plan/apply (more reliable than -var alone).
tf_export_dev_vars() {
  tf_common_vars
  : "${TF_BACKEND_BUCKET:?Set TF_BACKEND_BUCKET or TF_STATE_BUCKET (bootstrap state bucket)}"

  if [ -z "${TF_STATE_KMS_KEY_ARN:-}" ]; then
    echo "::warning::TF_STATE_KMS_KEY_ARN is unset (partial bootstrap); EKS KMS settings may be incomplete until bootstrap apply completes." >&2
  fi

  export TF_VAR_state_kms_key_arn="${TF_STATE_KMS_KEY_ARN:-}"
  export TF_VAR_state_bucket_name="${TF_BACKEND_BUCKET}"
  export TF_VAR_state_kms_key_id="${TF_BACKEND_KMS_KEY_ID:-}"
  export TF_VAR_dynamodb_table_name="${TF_BACKEND_DYNAMODB_TABLE:-}"
}

eks_cluster_name() {
  tf_common_vars
  printf '%s\n' "${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-eks"
}

eks_cluster_exists_in_aws() {
  local cluster_name="$1"
  aws eks describe-cluster --name "${cluster_name}" --region "${AWS_REGION}" &>/dev/null
}

eks_cluster_in_state() {
  local cluster_addr="${1:-module.eks.aws_eks_cluster.main}"
  terraform state show -no-color "${cluster_addr}" &>/dev/null
}

# True when terraform plan wants to create or replace the EKS cluster (replace triggers CreateCluster → 409).
eks_cluster_plan_wants_recreate() {
  local cluster_addr="${1:-module.eks.aws_eks_cluster.main}"
  local plan_log
  plan_log="$(mktemp)"

  terraform plan -input=false -no-color >"${plan_log}" 2>&1 || true

  if grep -qF "${cluster_addr} will be created" "${plan_log}" \
    || grep -qF 'aws_eks_cluster.main will be created' "${plan_log}" \
    || grep -qF "${cluster_addr} must be replaced" "${plan_log}" \
    || grep -qF 'aws_eks_cluster.main must be replaced' "${plan_log}"; then
    rm -f "${plan_log}"
    return 0
  fi

  rm -f "${plan_log}"
  return 1
}

# Import or verify the cluster when AWS has it but Terraform plans to create it.
recover_eks_cluster_before_apply() {
  local dev_abs="${1:-environments/dev}"
  local cluster_name cluster_addr
  local did_pushd=false

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  tf_init_s3_backend "${dev_abs}" dev/terraform.tfstate
  cluster_name="$(eks_cluster_name)"
  cluster_addr="module.eks.aws_eks_cluster.main"

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    echo "EKS cluster ${cluster_name} not in AWS; apply will create it."
    [ "${did_pushd}" = true ] && popd >/dev/null
    return 0
  fi

  if ! eks_cluster_in_state "${cluster_addr}"; then
    echo "${cluster_addr} missing from state but cluster exists in AWS; importing."
    if ! ensure_eks_cluster_imported "${dev_abs}"; then
      dev_import_diagnostics "${dev_abs}"
      [ "${did_pushd}" = true ] && popd >/dev/null
      return 1
    fi
  elif ! eks_cluster_plan_wants_recreate "${cluster_addr}"; then
    echo "${cluster_addr} is in state and plan does not recreate it; OK to apply."
    [ "${did_pushd}" = true ] && popd >/dev/null
    return 0
  else
    echo "::error::${cluster_addr} is in state but plan wants to create/replace the cluster (config drift)."
    echo "::error::Common causes: access_config authentication_mode change or cluster version mismatch."
    echo "::error::This module omits access_config by default on imports. Pull latest main and re-run apply."
    terraform plan -input=false -no-color || true
    [ "${did_pushd}" = true ] && popd >/dev/null
    return 1
  fi

  if eks_cluster_plan_wants_recreate "${cluster_addr}"; then
    echo "::error::Plan still wants to create/replace ${cluster_addr} after import."
    terraform plan -input=false -no-color || true
    [ "${did_pushd}" = true ] && popd >/dev/null
    return 1
  fi

  echo "Cluster recovered in state; safe to apply."
  [ "${did_pushd}" = true ] && popd >/dev/null
}

# Print context when debugging import/state issues in CI.
dev_import_diagnostics() {
  local dev_abs="${1:-environments/dev}"
  local cluster_name
  local did_pushd=false

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"

  echo "=== Dev import diagnostics ==="
  echo "AWS_REGION=${AWS_REGION}"
  echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"
  echo "TF_PROJECT_NAME=${TF_PROJECT_NAME}"
  echo "TF_ENVIRONMENT=${TF_ENVIRONMENT}"
  echo "TF_BACKEND_BUCKET=${TF_BACKEND_BUCKET}"
  echo "Expected cluster: ${cluster_name}"
  echo "State key: dev/terraform.tfstate"
  echo "Dev directory: ${dev_abs}"
  aws sts get-caller-identity
  if eks_cluster_exists_in_aws "${cluster_name}"; then
    echo "AWS: cluster EXISTS (describe-cluster OK)"
  else
    echo "AWS: cluster NOT FOUND (describe-cluster failed)"
  fi

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi
  if terraform state show -no-color module.eks.aws_eks_cluster.main &>/dev/null; then
    echo "Terraform state: module.eks.aws_eks_cluster.main is present"
  else
    echo "Terraform state: module.eks.aws_eks_cluster.main is MISSING"
  fi
  echo "EKS-related state addresses:"
  terraform state list -no-color 2>/dev/null | grep -E 'module\.eks|eks_cluster' || echo "(none)"
  [ "${did_pushd}" = true ] && popd >/dev/null
}

tf_backend_config_args() {
  : "${TF_BACKEND_BUCKET:?Set TF_BACKEND_BUCKET}"
  : "${TF_BACKEND_REGION:?Set TF_BACKEND_REGION}"

  printf '%s\n' \
    "-backend-config=bucket=${TF_BACKEND_BUCKET}" \
    "-backend-config=key=${TF_BACKEND_KEY}" \
    "-backend-config=region=${TF_BACKEND_REGION}" \
    "-backend-config=encrypt=true" \
    "-backend-config=use_lockfile=true"
  if [ -n "${TF_BACKEND_KMS_KEY_ID:-}" ]; then
    printf '%s\n' "-backend-config=kms_key_id=${TF_BACKEND_KMS_KEY_ID}"
  fi
}

bootstrap_state_bucket_name() {
  tf_common_vars
  printf '%s\n' "${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-state-${AWS_ACCOUNT_ID}"
}

bootstrap_state_bucket_exists() {
  local bucket
  bucket="$(bootstrap_state_bucket_name)"
  aws s3api head-bucket --bucket "${bucket}" &>/dev/null
}

bootstrap_dynamodb_table_name() {
  tf_common_vars
  printf '%s\n' "${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-locks"
}

bootstrap_dynamodb_table_exists() {
  local table="${1:-$(bootstrap_dynamodb_table_name)}"
  aws dynamodb describe-table --table-name "${table}" --region "${AWS_REGION}" &>/dev/null
}

bootstrap_kms_alias_name() {
  tf_common_vars
  printf '%s\n' "alias/${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-state"
}

bootstrap_kms_alias_exists() {
  local kms_alias
  kms_alias="$(bootstrap_kms_alias_name)"
  aws kms describe-key --key-id "${kms_alias}" &>/dev/null
}

# Remote backend is only usable after a full bootstrap (bucket + KMS alias).
bootstrap_remote_backend_ready() {
  bootstrap_state_bucket_exists && bootstrap_kms_alias_exists
}

# True only for a brand-new bootstrap (no state bucket in AWS yet).
# Terraform 1.7+ requires a configured S3 backend for import/plan when backend "s3" is declared;
# if the bucket already exists, init the S3 backend instead of -backend=false.
bootstrap_uses_local_state() {
  [ -z "${TF_STATE_BUCKET:-}" ] && ! bootstrap_state_bucket_exists
}

# No extra CLI args: local state is established by bootstrap_init -backend=false.
# Do not pass -state=terraform.tfstate; with backend "s3" in backend.tf that triggers
# "Backend initialization required" on import/plan/apply in Terraform 1.7+.
bootstrap_local_state_args() {
  :
}

bootstrap_set_backend_from_aws() {
  tf_common_vars
  export TF_BACKEND_BUCKET
  TF_BACKEND_BUCKET="$(bootstrap_state_bucket_name)"
  export TF_BACKEND_DYNAMODB_TABLE="${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-locks"
  export TF_BACKEND_REGION="${AWS_REGION}"
  export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"

  local kms_alias
  kms_alias="$(bootstrap_kms_alias_name)"
  if ! bootstrap_kms_alias_exists; then
    echo "::warning::KMS alias ${kms_alias} not found; remote backend is not ready." >&2
    return 1
  fi
  export TF_BACKEND_KMS_KEY_ID
  TF_BACKEND_KMS_KEY_ID="$(aws kms describe-key --key-id "${kms_alias}" --query 'KeyMetadata.KeyId' --output text)"
  export TF_STATE_KMS_KEY_ARN
  TF_STATE_KMS_KEY_ARN="$(aws kms describe-key --key-id "${kms_alias}" --query 'KeyMetadata.Arn' --output text)"
}

# KMS key ID used to encrypt the existing state bucket (if SSE-KMS), else empty.
bootstrap_kms_key_id_from_state_bucket() {
  local bucket sse kms_master
  bucket="$(bootstrap_state_bucket_name)"
  sse="$(aws s3api get-bucket-encryption --bucket "${bucket}" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
    --output text 2>/dev/null || true)"
  if [ "${sse}" != "aws:kms" ]; then
    return 1
  fi
  kms_master="$(aws s3api get-bucket-encryption --bucket "${bucket}" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID' \
    --output text 2>/dev/null || true)"
  if [ -z "${kms_master}" ] || [ "${kms_master}" = "None" ] || [ "${kms_master}" = "null" ]; then
    return 1
  fi
  aws kms describe-key --key-id "${kms_master}" --query 'KeyMetadata.KeyId' --output text 2>/dev/null
}

# Resolve bootstrap KMS key ID from alias, env, or bucket default encryption.
bootstrap_resolve_kms_key_id() {
  local key_id kms_alias

  if [ -n "${TF_BACKEND_KMS_KEY_ID:-}" ]; then
    printf '%s\n' "${TF_BACKEND_KMS_KEY_ID}"
    return 0
  fi
  if [ -n "${TF_STATE_KMS_KEY_ID:-}" ]; then
    printf '%s\n' "${TF_STATE_KMS_KEY_ID}"
    return 0
  fi
  if [ -n "${TF_STATE_KMS_KEY_ARN:-}" ]; then
    aws kms describe-key --key-id "${TF_STATE_KMS_KEY_ARN}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' --output text 2>/dev/null
    return 0
  fi
  kms_alias="$(bootstrap_kms_alias_name)"
  if bootstrap_kms_alias_exists; then
    aws kms describe-key --key-id "${kms_alias}" --query 'KeyMetadata.KeyId' --output text
    return 0
  fi
  bootstrap_kms_key_id_from_state_bucket
}

# Cancel scheduled KMS deletion so S3 state read/write works during destroy.
bootstrap_cancel_kms_pending_deletion() {
  local key_id="${1:-}" state

  if [ -z "${key_id}" ]; then
    if ! key_id="$(bootstrap_resolve_kms_key_id 2>/dev/null)"; then
      echo "No bootstrap KMS key found to check for pending deletion."
      return 0
    fi
  fi
  key_id="$(aws kms describe-key --key-id "${key_id}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.KeyId' --output text 2>/dev/null || printf '%s' "${key_id}")"

  state="$(aws kms describe-key --key-id "${key_id}" \
    --query 'KeyMetadata.KeyState' --output text 2>/dev/null || true)"
  if [ "${state}" != "PendingDeletion" ]; then
    echo "Bootstrap KMS key ${key_id} state: ${state:-unknown}"
    return 0
  fi

  echo "Cancelling KMS key pending deletion: ${key_id}"
  aws kms cancel-key-deletion --key-id "${key_id}" --region "${AWS_REGION}" >/dev/null
  local attempt=0
  while [ "${attempt}" -lt 30 ]; do
    state="$(aws kms describe-key --key-id "${key_id}" \
      --query 'KeyMetadata.KeyState' --output text 2>/dev/null || true)"
    if [ "${state}" = "Enabled" ]; then
      echo "Bootstrap KMS key ${key_id} is Enabled again."
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  echo "::warning::KMS key ${key_id} not Enabled after cancel (state=${state})." >&2
  return 1
}

# Recreate bootstrap KMS alias when it was deleted but the key still exists.
bootstrap_ensure_kms_alias() {
  local key_id kms_alias target

  kms_alias="$(bootstrap_kms_alias_name)"
  if ! key_id="$(bootstrap_resolve_kms_key_id 2>/dev/null)"; then
    echo "::error::Cannot resolve bootstrap KMS key ID to attach alias ${kms_alias}." >&2
    return 1
  fi

  if bootstrap_kms_alias_exists; then
    target="$(aws kms describe-key --key-id "${kms_alias}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' --output text)"
    if [ "${target}" = "${key_id}" ]; then
      echo "KMS alias ${kms_alias} already points to key ${key_id}."
      return 0
    fi
    echo "Updating KMS alias ${kms_alias} -> key ${key_id} (was ${target})..."
    aws kms update-alias \
      --alias-name "${kms_alias}" \
      --target-key-id "${key_id}" \
      --region "${AWS_REGION}"
    return 0
  fi

  echo "Creating KMS alias ${kms_alias} -> key ${key_id}..."
  aws kms create-alias \
    --alias-name "${kms_alias}" \
    --target-key-id "${key_id}" \
    --region "${AWS_REGION}"
}

# Recover bootstrap KMS after failed destroy: cancel pending deletion and restore alias.
# Usage: bootstrap_recover_kms [key-id-or-arn]
bootstrap_recover_kms() {
  local key_override="${1:-}" key_id kms_alias

  tf_common_vars
  kms_alias="$(bootstrap_kms_alias_name)"

  if [ -n "${key_override}" ]; then
    key_id="$(aws kms describe-key --key-id "${key_override}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' --output text)"
    export TF_BACKEND_KMS_KEY_ID="${key_id}"
    export TF_STATE_KMS_KEY_ARN
    TF_STATE_KMS_KEY_ARN="$(aws kms describe-key --key-id "${key_id}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.Arn' --output text)"
  fi

  bootstrap_cancel_kms_pending_deletion "${key_override}" || return 1
  bootstrap_ensure_kms_alias || return 1

  key_id="$(bootstrap_resolve_kms_key_id)"
  export TF_BACKEND_KMS_KEY_ID="${key_id}"
  export TF_STATE_KMS_KEY_ARN
  TF_STATE_KMS_KEY_ARN="$(aws kms describe-key --key-id "${key_id}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.Arn' --output text)"

  if bootstrap_state_bucket_exists; then
    export TF_BACKEND_BUCKET="$(bootstrap_state_bucket_name)"
    export TF_BACKEND_REGION="${AWS_REGION}"
    export TF_BACKEND_DYNAMODB_TABLE="$(bootstrap_dynamodb_table_name)"
    export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"
  fi

  echo "Bootstrap KMS recovery complete."
  echo "  Alias: ${kms_alias}"
  echo "  Key ID: ${key_id}"
  echo "  Key ARN: ${TF_STATE_KMS_KEY_ARN}"
  echo "Next: bootstrap_init global/bootstrap  (or re-run the Terraform workflow)"
}

# Delete every version/delete-marker for one exact S3 object key.
bootstrap_delete_s3_object_all_versions() {
  local bucket="$1" object_key="$2"
  local version_id

  while read -r version_id; do
    [ -z "${version_id}" ] || [ "${version_id}" = "None" ] && continue
    aws s3api delete-object \
      --bucket "${bucket}" \
      --key "${object_key}" \
      --version-id "${version_id}" \
      --region "${AWS_REGION}" >/dev/null 2>&1 || true
  done < <(aws s3api list-object-versions \
    --bucket "${bucket}" \
    --prefix "${object_key}" \
    --region "${AWS_REGION}" \
    --query "Versions[?Key=='${object_key}'].VersionId" \
    --output text 2>/dev/null | tr '\t' '\n')

  while read -r version_id; do
    [ -z "${version_id}" ] || [ "${version_id}" = "None" ] && continue
    aws s3api delete-object \
      --bucket "${bucket}" \
      --key "${object_key}" \
      --version-id "${version_id}" \
      --region "${AWS_REGION}" >/dev/null 2>&1 || true
  done < <(aws s3api list-object-versions \
    --bucket "${bucket}" \
    --prefix "${object_key}" \
    --region "${AWS_REGION}" \
    --query "DeleteMarkers[?Key=='${object_key}'].VersionId" \
    --output text 2>/dev/null | tr '\t' '\n')
}

# Empty a versioned state bucket (required when force_destroy cannot complete).
bootstrap_empty_state_bucket_all_versions() {
  local bucket="$1" key version_id deleted=0

  if ! aws s3api head-bucket --bucket "${bucket}" --region "${AWS_REGION}" 2>/dev/null; then
    return 0
  fi

  echo "Deleting all object versions from s3://${bucket}..."
  while read -r key version_id; do
    [ -z "${key}" ] && continue
    aws s3api delete-object \
      --bucket "${bucket}" \
      --key "${key}" \
      --version-id "${version_id}" \
      --region "${AWS_REGION}" >/dev/null 2>&1 || true
    deleted=$((deleted + 1))
  done < <(aws s3api list-object-versions \
    --bucket "${bucket}" \
    --region "${AWS_REGION}" \
    --output text \
    --query 'Versions[].[Key,VersionId]' 2>/dev/null)

  while read -r key version_id; do
    [ -z "${key}" ] && continue
    aws s3api delete-object \
      --bucket "${bucket}" \
      --key "${key}" \
      --version-id "${version_id}" \
      --region "${AWS_REGION}" >/dev/null 2>&1 || true
    deleted=$((deleted + 1))
  done < <(aws s3api list-object-versions \
    --bucket "${bucket}" \
    --region "${AWS_REGION}" \
    --output text \
    --query 'DeleteMarkers[].[Key,VersionId]' 2>/dev/null)

  echo "Removed ${deleted} versioned object(s) from ${bucket}."
}

# S3 native lockfiles (use_lockfile=true); separate from legacy DynamoDB lock rows.
clear_s3_state_lockfiles() {
  local bucket="${1:-}"
  local state_key

  if [ -z "${bucket}" ]; then
    resolve_bootstrap_backend_env "$(bootstrap_dir_abs global/bootstrap)" || return 0
    bucket="${TF_BACKEND_BUCKET}"
  fi
  if ! aws s3api head-bucket --bucket "${bucket}" --region "${AWS_REGION}" 2>/dev/null; then
    return 0
  fi

  echo "Removing S3 state lockfiles from ${bucket}..."
  for state_key in \
    "global/bootstrap/terraform.tfstate" \
    "global/policies/terraform.tfstate" \
    "dev/terraform.tfstate"; do
    bootstrap_delete_s3_object_all_versions "${bucket}" "${state_key}.tflock"
  done
}

bootstrap_s3_bucket_versioning_exists() {
  local bucket="$1"
  local status
  status="$(aws s3api get-bucket-versioning --bucket "${bucket}" \
    --query 'Status' --output text 2>/dev/null || true)"
  [ -n "${status}" ] && [ "${status}" != "None" ] && [ "${status}" != "null" ]
}

bootstrap_s3_bucket_encryption_exists() {
  aws s3api get-bucket-encryption --bucket "$1" &>/dev/null
}

bootstrap_s3_bucket_public_access_block_exists() {
  aws s3api get-public-access-block --bucket "$1" &>/dev/null
}

bootstrap_precheck_report() {
  tf_common_vars

  local bucket table kms_alias
  local -a existing_items=()
  local -a missing_items=()
  local kms_from_bucket=""
  bucket="$(bootstrap_state_bucket_name)"
  table="$(bootstrap_dynamodb_table_name)"
  kms_alias="$(bootstrap_kms_alias_name)"

  if bootstrap_state_bucket_exists; then
    existing_items+=("s3_bucket")
    if bootstrap_s3_bucket_versioning_exists "${bucket}"; then
      existing_items+=("s3_bucket_versioning")
    else
      missing_items+=("s3_bucket_versioning")
    fi
    if bootstrap_s3_bucket_encryption_exists "${bucket}"; then
      existing_items+=("s3_bucket_sse")
    else
      missing_items+=("s3_bucket_sse")
    fi
    if bootstrap_s3_bucket_public_access_block_exists "${bucket}"; then
      existing_items+=("s3_public_access_block")
    else
      missing_items+=("s3_public_access_block")
    fi
  else
    missing_items+=("s3_bucket" "s3_bucket_versioning" "s3_bucket_sse" "s3_public_access_block")
  fi

  if bootstrap_kms_alias_exists; then
    existing_items+=("kms_alias")
  else
    missing_items+=("kms_alias")
  fi

  if kms_from_bucket="$(bootstrap_kms_key_id_from_state_bucket 2>/dev/null)"; then
    if [ -n "${kms_from_bucket}" ]; then
      existing_items+=("kms_key_reference")
    fi
  fi
  if [ -z "${kms_from_bucket}" ] && ! bootstrap_kms_alias_exists; then
    missing_items+=("kms_key_reference")
  fi

  if bootstrap_dynamodb_table_exists "${table}"; then
    existing_items+=("dynamodb_lock_table")
  else
    missing_items+=("dynamodb_lock_table")
  fi

  local status="ready"
  if [ "${#missing_items[@]}" -gt 0 ] && [ "${#existing_items[@]}" -eq 0 ]; then
    status="fresh"
  elif [ "${#missing_items[@]}" -gt 0 ]; then
    status="partial"
  fi

  export BOOTSTRAP_PRECHECK_STATUS="${status}"
  echo "Bootstrap precheck status: ${status}"
  echo "Expected primary services: KMS, S3, DynamoDB"
  if [ "${#existing_items[@]}" -gt 0 ]; then
    echo "Existing bootstrap items: ${existing_items[*]}"
  else
    echo "Existing bootstrap items: none"
  fi
  if [ "${#missing_items[@]}" -gt 0 ]; then
    echo "Missing bootstrap items: ${missing_items[*]}"
    echo "Proceeding with import/apply to reconcile missing resources."
  else
    echo "Missing bootstrap items: none"
  fi
}

# Partial bootstrap: S3 bucket exists; discover KMS from alias or bucket default encryption.
bootstrap_set_backend_for_existing_bucket() {
  tf_common_vars
  export TF_BACKEND_BUCKET
  TF_BACKEND_BUCKET="$(bootstrap_state_bucket_name)"
  export TF_BACKEND_DYNAMODB_TABLE="${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-locks"
  export TF_BACKEND_REGION="${AWS_REGION}"
  export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"
  unset TF_BACKEND_KMS_KEY_ID TF_STATE_KMS_KEY_ARN

  if bootstrap_kms_alias_exists; then
    local kms_alias
    kms_alias="$(bootstrap_kms_alias_name)"
    export TF_BACKEND_KMS_KEY_ID
    TF_BACKEND_KMS_KEY_ID="$(aws kms describe-key --key-id "${kms_alias}" --query 'KeyMetadata.KeyId' --output text)"
    export TF_STATE_KMS_KEY_ARN
    TF_STATE_KMS_KEY_ARN="$(aws kms describe-key --key-id "${kms_alias}" --query 'KeyMetadata.Arn' --output text)"
    return 0
  fi

  local key_id
  if key_id="$(bootstrap_kms_key_id_from_state_bucket)"; then
    export TF_BACKEND_KMS_KEY_ID="${key_id}"
    export TF_STATE_KMS_KEY_ARN
    TF_STATE_KMS_KEY_ARN="$(aws kms describe-key --key-id "${key_id}" --query 'KeyMetadata.Arn' --output text)"
    echo "Using KMS key ${key_id} from existing state bucket encryption (no alias yet)." >&2
  else
    echo "State bucket exists without SSE-KMS; S3 backend will use bucket default encryption for state." >&2
    export TF_BACKEND_KMS_KEY_ID=""
    export TF_STATE_KMS_KEY_ARN=""
  fi
}

# Resolve TF_BACKEND_* for plan/destroy when bootstrap was applied in a previous run.
resolve_bootstrap_backend_env() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"

  if [ -n "${TF_STATE_BUCKET:-}" ] \
    && [ -n "${TF_STATE_KMS_KEY_ID:-}" ] \
    && [ -n "${TF_STATE_DYNAMODB_TABLE:-}" ] \
    && [ -n "${TF_STATE_KMS_KEY_ARN:-}" ]; then
    export TF_BACKEND_BUCKET="${TF_STATE_BUCKET}"
    export TF_BACKEND_KMS_KEY_ID="${TF_STATE_KMS_KEY_ID}"
    export TF_BACKEND_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE}"
    export TF_STATE_KMS_KEY_ARN="${TF_STATE_KMS_KEY_ARN}"
    export TF_BACKEND_REGION="${AWS_REGION}"
    echo "Using bootstrap backend from repository variables."
    return 0
  fi

  if bootstrap_remote_backend_ready; then
    bootstrap_set_backend_from_aws
    echo "Using bootstrap backend from existing S3 bucket and KMS alias in AWS."
    return 0
  fi

  if bootstrap_state_bucket_exists; then
    bootstrap_set_backend_for_existing_bucket
    echo "Using bootstrap backend from existing state bucket (partial bootstrap)."
    return 0
  fi

  if [ -f "${bootstrap_dir}/terraform.tfstate" ]; then
    bootstrap_init "${bootstrap_dir}"
    export_bootstrap_outputs "${bootstrap_dir}"
    echo "Using bootstrap outputs from local terraform.tfstate."
    return 0
  fi

  echo "::error::Bootstrap remote state values are required." >&2
  echo "::error::Set repository variables TF_STATE_BUCKET, TF_STATE_KMS_KEY_ID, TF_STATE_DYNAMODB_TABLE, TF_STATE_KMS_KEY_ARN," >&2
  echo "::error::or run apply for global/bootstrap first." >&2
  return 1
}

# Write TF_BACKEND_* to GITHUB_ENV (plan / destroy / apply after bootstrap).
export_bootstrap_backend_env() {
  local bootstrap_dir operation target
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  operation="${2:-}"
  target="${3:-}"

  if [ "${operation}" = "apply" ] \
    && { [ "${target}" = "all" ] || [ "${target}" = "global/bootstrap" ]; }; then
    export_bootstrap_outputs "${bootstrap_dir}"
  else
    resolve_bootstrap_backend_env "${bootstrap_dir}"
  fi

  {
    echo "TF_BACKEND_BUCKET=${TF_BACKEND_BUCKET}"
    echo "TF_BACKEND_KMS_KEY_ID=${TF_BACKEND_KMS_KEY_ID:-}"
    echo "TF_BACKEND_DYNAMODB_TABLE=${TF_BACKEND_DYNAMODB_TABLE:-}"
    echo "TF_STATE_KMS_KEY_ARN=${TF_STATE_KMS_KEY_ARN:-}"
    echo "TF_BACKEND_REGION=${TF_BACKEND_REGION}"
  } >> "${GITHUB_ENV}"
}

export_bootstrap_outputs() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  pushd "${bootstrap_dir}" >/dev/null
  mapfile -t state_args < <(bootstrap_local_state_args)

  export TF_BACKEND_BUCKET
  TF_BACKEND_BUCKET="$(terraform output -raw "${state_args[@]}" state_bucket_name)"
  export TF_BACKEND_KMS_KEY_ID
  TF_BACKEND_KMS_KEY_ID="$(terraform output -raw "${state_args[@]}" kms_key_id)"
  export TF_BACKEND_DYNAMODB_TABLE
  TF_BACKEND_DYNAMODB_TABLE="$(terraform output -raw "${state_args[@]}" dynamodb_table_name)"
  export TF_STATE_KMS_KEY_ARN
  TF_STATE_KMS_KEY_ARN="$(terraform output -raw "${state_args[@]}" kms_key_arn)"
  export TF_BACKEND_REGION="${AWS_REGION}"

  popd >/dev/null
}

tf_init_s3_backend() {
  local dir state_key
  dir="$(repo_path "$1")"
  state_key="$2"
  pushd "${dir}" >/dev/null
  export TF_BACKEND_KEY="${state_key}"
  mapfile -t backend_args < <(tf_backend_config_args)
  terraform init -input=false "${backend_args[@]}"
  popd >/dev/null
}

maybe_migrate_bootstrap_state() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"

  if [ -n "${TF_STATE_BUCKET:-}" ]; then
    bootstrap_enable_state_locking "${bootstrap_dir}"
    return 0
  fi

  export_bootstrap_outputs "${bootstrap_dir}"
  pushd "${bootstrap_dir}" >/dev/null
  export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"
  mapfile -t backend_args < <(tf_backend_config_args)
  terraform init -input=false -migrate-state -force-copy "${backend_args[@]}"
  popd >/dev/null
  bootstrap_enable_state_locking "${bootstrap_dir}"
}

# Re-init bootstrap backend with S3 lockfile-based state locking.
bootstrap_enable_state_locking() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  tf_common_vars

  pushd "${bootstrap_dir}" >/dev/null
  if [ -n "${TF_STATE_BUCKET:-}" ]; then
    export TF_BACKEND_BUCKET="${TF_STATE_BUCKET}"
    export TF_BACKEND_KMS_KEY_ID="${TF_STATE_KMS_KEY_ID:-}"
    export TF_BACKEND_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"
    export TF_STATE_KMS_KEY_ARN="${TF_STATE_KMS_KEY_ARN:-}"
    export TF_BACKEND_REGION="${AWS_REGION}"
    if [ -z "${TF_BACKEND_KMS_KEY_ID}" ] && bootstrap_state_bucket_exists; then
      bootstrap_set_backend_for_existing_bucket
    fi
  elif bootstrap_state_bucket_exists; then
    bootstrap_set_backend_for_existing_bucket
  else
    popd >/dev/null
    return 0
  fi
  export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"
  echo "Enabling S3 lockfile state locking..."
  mapfile -t backend_args < <(tf_backend_config_args)
  terraform init -input=false -reconfigure "${backend_args[@]}"
  popd >/dev/null
}

bootstrap_init() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  pushd "${bootstrap_dir}" >/dev/null

  if [ -n "${TF_STATE_BUCKET:-}" ]; then
    export TF_BACKEND_BUCKET="${TF_STATE_BUCKET}"
    export TF_BACKEND_KMS_KEY_ID="${TF_STATE_KMS_KEY_ID:-}"
    export TF_BACKEND_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"
    export TF_STATE_KMS_KEY_ARN="${TF_STATE_KMS_KEY_ARN:-}"
    export TF_BACKEND_REGION="${AWS_REGION}"
    if [ -z "${TF_BACKEND_KMS_KEY_ID}" ] && bootstrap_state_bucket_exists; then
      bootstrap_set_backend_for_existing_bucket
    fi
    export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"
    mapfile -t backend_args < <(tf_backend_config_args)
    terraform init -input=false "${backend_args[@]}"
  elif bootstrap_remote_backend_ready; then
    # Bootstrap was applied previously; use remote state even without TF_STATE_* vars.
    bootstrap_set_backend_from_aws
    mapfile -t backend_args < <(tf_backend_config_args)
    terraform init -input=false -reconfigure "${backend_args[@]}"
  elif bootstrap_state_bucket_exists; then
    # Bucket exists (partial bootstrap). Init S3 backend so import/plan work on Terraform 1.7+.
    bootstrap_set_backend_for_existing_bucket
    mapfile -t backend_args < <(tf_backend_config_args)
    terraform init -input=false -reconfigure "${backend_args[@]}"
  else
    # Brand-new bootstrap: no state bucket yet; local state until maybe_migrate_bootstrap_state.
    terraform init -input=false -backend=false
  fi

  popd >/dev/null
}

# Import bootstrap resources that already exist in AWS but are missing from state
# (for example after a partial apply or lost local state before S3 migration).
import_existing_bootstrap_resources() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  tf_common_vars

  # Each workflow step is a new shell; re-init so .terraform matches local vs remote backend.
  bootstrap_init "${bootstrap_dir}"

  local name_prefix="${TF_PROJECT_NAME}-${TF_ENVIRONMENT}"
  local state_bucket="${name_prefix}-terraform-state-${AWS_ACCOUNT_ID}"
  local dynamodb_table="${name_prefix}-terraform-locks"
  local kms_alias="alias/${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-state"

  pushd "${bootstrap_dir}" >/dev/null
  mapfile -t var_args < <(tf_var_args)
  mapfile -t state_args < <(bootstrap_local_state_args)

  terraform_state_has() {
    terraform state show -no-color "${state_args[@]}" "$1" &>/dev/null
  }

  import_if_missing() {
    local addr="$1"
    local id="$2"

    if terraform_state_has "${addr}"; then
      return 0
    fi

    echo "Importing existing bootstrap resource ${addr}..."
    terraform import -input=false "${state_args[@]}" "${var_args[@]}" "${addr}" "${id}"
  }

  if aws kms describe-key --key-id "${kms_alias}" &>/dev/null; then
    local key_id
    key_id="$(aws kms describe-key --key-id "${kms_alias}" --query 'KeyMetadata.KeyId' --output text)"
    import_if_missing aws_kms_key.terraform_state "${key_id}"
    import_if_missing aws_kms_alias.terraform_state "${kms_alias}"
  elif key_id="$(bootstrap_kms_key_id_from_state_bucket)"; then
    echo "Importing KMS key from state bucket encryption (alias not created yet)..."
    import_if_missing aws_kms_key.terraform_state "${key_id}"
  fi

  if aws s3api head-bucket --bucket "${state_bucket}" &>/dev/null; then
    import_if_missing aws_s3_bucket.terraform_state "${state_bucket}"
    if bootstrap_s3_bucket_versioning_exists "${state_bucket}"; then
      import_if_missing aws_s3_bucket_versioning.terraform_state "${state_bucket}"
    else
      echo "Skipping import of aws_s3_bucket_versioning.terraform_state (not configured on ${state_bucket}); apply will create it." >&2
    fi
    if bootstrap_s3_bucket_encryption_exists "${state_bucket}"; then
      import_if_missing aws_s3_bucket_server_side_encryption_configuration.terraform_state "${state_bucket}"
    else
      echo "Skipping import of aws_s3_bucket_server_side_encryption_configuration.terraform_state (not configured on ${state_bucket}); apply will create it." >&2
    fi
    if bootstrap_s3_bucket_public_access_block_exists "${state_bucket}"; then
      import_if_missing aws_s3_bucket_public_access_block.terraform_state "${state_bucket}"
    else
      echo "Skipping import of aws_s3_bucket_public_access_block.terraform_state (not configured on ${state_bucket}); apply will create it." >&2
    fi
  fi

  if aws dynamodb describe-table --table-name "${dynamodb_table}" &>/dev/null; then
    import_if_missing aws_dynamodb_table.terraform_state_lock "${dynamodb_table}"
  fi

  popd >/dev/null
}

# Import the EKS cluster into state when it already exists in AWS (required before apply).
ensure_eks_cluster_imported() {
  local dev_abs="${1:-environments/dev}"
  local did_pushd=false
  local cluster_name cluster_addr
  local import_out import_status

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"
  cluster_addr="module.eks.aws_eks_cluster.main"

  if [ ! -d "${dev_abs}" ]; then
    echo "::error::Dev directory not found: ${dev_abs}"
    return 1
  fi

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  echo "Checking EKS cluster ${cluster_name} (region ${AWS_REGION}, account ${AWS_ACCOUNT_ID})..."

  if terraform state show -no-color "${cluster_addr}" &>/dev/null; then
    echo "EKS cluster already in Terraform state."
    if [ "${did_pushd}" = true ]; then
      popd >/dev/null
    fi
    return 0
  fi

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    echo "EKS cluster ${cluster_name} not found in AWS; it will be created on apply."
    if [ "${did_pushd}" = true ]; then
      popd >/dev/null
    fi
    return 0
  fi

  echo "Importing existing EKS cluster ${cluster_name} into Terraform state..."
  set +e
  import_out="$(terraform import -input=false "${cluster_addr}" "${cluster_name}" 2>&1)"
  import_status=$?
  set -e
  echo "${import_out}"

  if [ "${import_status}" -eq 0 ]; then
    terraform state show -no-color "${cluster_addr}" >/dev/null
    echo "Successfully imported ${cluster_addr}."
    [ "${did_pushd}" = true ] && popd >/dev/null
    return 0
  fi

  if echo "${import_out}" | grep -q "Resource already managed by Terraform"; then
    echo "${cluster_addr} is already in Terraform state; continuing."
    [ "${did_pushd}" = true ] && popd >/dev/null
    return 0
  fi

  echo "::error::Cluster ${cluster_name} exists in AWS but Terraform import failed (see output above)."
  [ "${did_pushd}" = true ] && popd >/dev/null
  return 1
}

# Abort apply when the cluster exists in AWS but is still missing from state.
verify_eks_cluster_state() {
  local dev_abs="${1:-environments/dev}"
  local cluster_name cluster_addr
  local did_pushd=false

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"
  cluster_addr="module.eks.aws_eks_cluster.main"

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  if eks_cluster_exists_in_aws "${cluster_name}"; then
    if terraform state show -no-color "${cluster_addr}" &>/dev/null; then
      echo "Verified: ${cluster_name} is in AWS and Terraform state."
    else
      echo "::error::${cluster_name} exists in AWS but is not in Terraform state. Re-run import or run: terraform import ${cluster_addr} ${cluster_name}"
      [ "${did_pushd}" = true ] && popd >/dev/null
      return 1
    fi
  fi

  [ "${did_pushd}" = true ] && popd >/dev/null
}

# Explicit EKS cluster import for CI recovery (remove after state is healthy).
import_eks_cluster_recovery() {
  recover_eks_cluster_before_apply "${1:-environments/dev}"
}

# Upgrade CONFIG_MAP → API_AND_CONFIG_MAP in-place (required for aws_eks_access_entry).
upgrade_eks_authentication_mode_if_needed() {
  tf_export_dev_vars
  local cluster_name
  cluster_name="$(eks_cluster_name)"

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    return 0
  fi

  local repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  CLUSTER_NAME="${cluster_name}" AWS_REGION="${AWS_REGION}" \
    bash "${repo_root}/modules/eks/scripts/upgrade-eks-authentication-mode.sh"
}

# API_AND_CONFIG_MAP + aws-auth still yields Unauthorized on managed nodes; use API + EC2_LINUX.
migrate_dev_cluster_to_api_node_auth() {
  tf_export_dev_vars
  local cluster_name node_role_arn repo_root auth_mode
  cluster_name="$(eks_cluster_name)"

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    return 0
  fi

  node_role_arn="$(node_iam_role_arn "${cluster_name}")"
  repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"

  case "${auth_mode}" in
    API)
      echo "Cluster auth mode is API; ensuring EC2_LINUX access entry..."
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${AWS_REGION}" \
        bash "${repo_root}/modules/eks/scripts/ensure-node-cluster-auth.sh"
      ;;
    API_AND_CONFIG_MAP)
      echo "Migrating dev cluster from API_AND_CONFIG_MAP to API (managed nodes use EC2_LINUX access entries)..."
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${AWS_REGION}" \
        bash "${repo_root}/modules/eks/scripts/migrate-cluster-auth-to-api.sh"
      ;;
    CONFIG_MAP)
      echo "Cluster still CONFIG_MAP; upgrade step must run before API migration."
      return 0
      ;;
    *)
      echo "::warning::Unknown authentication mode ${auth_mode}; skipping API migration."
      return 0
      ;;
  esac

  CLUSTER_NAME="${cluster_name}" NODEGROUP_NAME="general" AWS_REGION="${AWS_REGION}" \
    bash "${repo_root}/modules/eks/scripts/recycle-nodegroup-instances.sh" || true
}

# Import access entry + policy association after CI scripts create them (avoids 409 on apply).
import_eks_node_access_to_state() {
  local dev_abs="${1:-environments/dev}"
  local cluster_name node_role_arn policy_arn
  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"
  node_role_arn="$(node_iam_role_arn "${cluster_name}")"
  policy_arn="arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodegroupPolicy"

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    return 0
  fi

  pushd "${dev_abs}" >/dev/null
  mapfile -t var_args < <(tf_var_args)
  mapfile -t dev_args < <(tf_dev_extra_var_args)

  if aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${AWS_REGION}" &>/dev/null; then
    if ! terraform state show -no-color 'module.eks.aws_eks_access_entry.node[0]' &>/dev/null; then
      echo "Importing node access entry into Terraform state..."
      terraform import -input=false "${var_args[@]}" "${dev_args[@]}" \
        'module.eks.aws_eks_access_entry.node[0]' "${cluster_name}:${node_role_arn}" || true
    fi
  fi

  if aws eks list-associated-access-policies \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${AWS_REGION}" \
    --query "associatedAccessPolicies[?policyArn=='${policy_arn}'].policyArn | [0]" \
    --output text 2>/dev/null | grep -q "${policy_arn}"; then
    if ! terraform state show -no-color 'module.eks.aws_eks_access_policy_association.node[0]' &>/dev/null; then
      echo "Importing node access policy association into Terraform state..."
      terraform import -input=false "${var_args[@]}" "${dev_args[@]}" \
        'module.eks.aws_eks_access_policy_association.node[0]' \
        "${cluster_name}#${node_role_arn}#${policy_arn}" || true
    fi
  fi

  popd >/dev/null
}

# Delete managed node groups that still use a custom launch template or instances without an IAM profile.
reset_stale_eks_managed_nodegroup() {
  tf_export_dev_vars
  local cluster_name nodegroup_name node_role_arn
  local lt_id lt_name ng_role status asg_name need_delete
  cluster_name="$(eks_cluster_name)"
  nodegroup_name="general"
  node_role_arn="$(node_iam_role_arn "${cluster_name}")"

  if ! aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" &>/dev/null; then
    return 0
  fi

  lt_id="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.launchTemplate.id' \
    --output text 2>/dev/null || echo "None")"
  lt_name="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.launchTemplate.name' \
    --output text 2>/dev/null || echo "None")"
  ng_role="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.nodeRole' \
    --output text 2>/dev/null || echo "")"
  status="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.status' \
    --output text)"

  echo "Node group ${nodegroup_name}: status=${status} nodeRole=${ng_role} launchTemplate=${lt_name}/${lt_id}"

  need_delete=false
  if [ -n "${lt_id}" ] && [ "${lt_id}" != "None" ]; then
    echo "::warning::Node group still uses custom launch template ${lt_name} (${lt_id}). EKS default templates attach the node instance profile; custom templates from older applies often do not."
    need_delete=true
  fi

  if [ -n "${ng_role}" ] && [ "${ng_role}" != "${node_role_arn}" ]; then
    echo "::warning::Node group nodeRole (${ng_role}) does not match expected (${node_role_arn})."
    need_delete=true
  fi

  asg_name="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.resources.autoScalingGroups[0].name' \
    --output text 2>/dev/null || true)"

  if [ -n "${asg_name}" ] && [ "${asg_name}" != "None" ]; then
    local iid profile_arn
    while read -r iid; do
      [ -z "${iid}" ] || [ "${iid}" = "None" ] && continue
      profile_arn="$(aws ec2 describe-instances --instance-ids "${iid}" --region "${AWS_REGION}" \
        --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text 2>/dev/null || echo "None")"
      echo "Instance ${iid} IamInstanceProfile=${profile_arn}"
      if [ -z "${profile_arn}" ] || [ "${profile_arn}" = "None" ]; then
        echo "::error::Instance ${iid} has no IAM instance profile (kubelet cannot authenticate)."
        need_delete=true
      fi
    done < <(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "${asg_name}" \
      --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
      --output text 2>/dev/null | tr '\t' '\n')
  fi

  if [ "${need_delete}" = true ]; then
    echo "Deleting node group ${nodegroup_name} for clean recreate without stale launch template..."
    aws eks delete-nodegroup \
      --cluster-name "${cluster_name}" \
      --nodegroup-name "${nodegroup_name}" \
      --region "${AWS_REGION}" || true
    aws eks wait nodegroup-deleted \
      --cluster-name "${cluster_name}" \
      --nodegroup-name "${nodegroup_name}" \
      --region "${AWS_REGION}" || true
    if [ -d "environments/dev/.terraform" ] || [ -d "$(resolve_dev_dir environments/dev)/.terraform" ]; then
      local dev_abs
      dev_abs="$(resolve_dev_dir environments/dev)"
      pushd "${dev_abs}" >/dev/null
      terraform state rm 'module.eks.aws_eks_node_group.main["general"]' 2>/dev/null || true
      popd >/dev/null
    fi
  fi
}

# Delete node groups stuck in CREATE_FAILED so the next apply can recreate them.
delete_failed_eks_node_groups() {
  local dev_abs="${1:-environments/dev}"
  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  local cluster_name nodegroup_name status
  cluster_name="$(eks_cluster_name)"
  nodegroup_name="general"

  if ! aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" &>/dev/null; then
    return 0
  fi

  status="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.status' \
    --output text)"

  case "${status}" in
    CREATE_FAILED)
      echo "Deleting failed node group ${nodegroup_name} (status=${status})..."
      aws eks delete-nodegroup \
        --cluster-name "${cluster_name}" \
        --nodegroup-name "${nodegroup_name}" \
        --region "${AWS_REGION}"
      aws eks wait nodegroup-deleted \
        --cluster-name "${cluster_name}" \
        --nodegroup-name "${nodegroup_name}" \
        --region "${AWS_REGION}"
      if [ -d "${dev_abs}/.terraform" ]; then
        pushd "${dev_abs}" >/dev/null
        terraform state rm 'module.eks.aws_eks_node_group.main["general"]' 2>/dev/null || true
        popd >/dev/null
      fi
      ;;
    DELETING)
      echo "Waiting for node group ${nodegroup_name} deletion..."
      aws eks wait nodegroup-deleted \
        --cluster-name "${cluster_name}" \
        --nodegroup-name "${nodegroup_name}" \
        --region "${AWS_REGION}"
      ;;
  esac
}

# Drop stale launch template state (launch template removed from module).
cleanup_stale_eks_auth_state() {
  local dev_abs="${1:-environments/dev}"
  local did_pushd=false

  dev_abs="$(resolve_dev_dir "${dev_abs}")"

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  terraform state rm 'module.eks.aws_launch_template.node_group["general"]' 2>/dev/null || true
  terraform state rm 'module.eks.kubernetes_config_map_v1.aws_auth[0]' 2>/dev/null || true
  terraform state rm 'module.eks.aws_eks_access_entry.node[0]' 2>/dev/null || true

  [ "${did_pushd}" = true ] && popd >/dev/null
}

apply_eks_public_endpoint_if_needed() {
  local dev_abs="${1:-environments/dev}"
  local cluster_name did_pushd=false

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    return 0
  fi

  local public_access
  public_access="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.resourcesVpcConfig.endpointPublicAccess' \
    --output text 2>/dev/null || echo "False")"

  if [ "${public_access}" = "True" ]; then
    echo "EKS public API endpoint is already enabled."
    return 0
  fi

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  mapfile -t var_args < <(tf_var_args)
  mapfile -t dev_args < <(tf_dev_extra_var_args)

  echo "Enabling public EKS API endpoint (targeted) so CI can apply aws-auth..."
  terraform apply -input=false -auto-approve -no-color \
    "${var_args[@]}" "${dev_args[@]}" \
    -target='module.eks.aws_eks_cluster.main'

  [ "${did_pushd}" = true ] && popd >/dev/null
}

node_iam_role_arn() {
  local cluster_name="${1:-$(eks_cluster_name)}"
  aws iam get-role \
    --role-name "${cluster_name}-node" \
    --query 'Role.Arn' \
    --output text
}

ensure_node_cluster_auth_for_dev() {
  tf_export_dev_vars
  local cluster_name node_role_arn repo_root
  cluster_name="$(eks_cluster_name)"

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    return 0
  fi

  node_role_arn="$(node_iam_role_arn "${cluster_name}")"
  repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

  python3 -c "import yaml" 2>/dev/null || pip install --user pyyaml

  echo "Ensuring node cluster auth for ${node_role_arn}..."
  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${AWS_REGION}" \
    bash "${repo_root}/modules/eks/scripts/ensure-node-cluster-auth.sh"

  aws eks update-kubeconfig --name "${cluster_name}" --region "${AWS_REGION}" >/dev/null
  local auth_mode
  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"

  case "${auth_mode}" in
    API)
      if ! aws eks describe-access-entry \
        --cluster-name "${cluster_name}" \
        --principal-arn "${node_role_arn}" \
        --region "${AWS_REGION}" &>/dev/null; then
        echo "::error::Node access entry missing for API mode cluster."
        return 1
      fi
      echo "Node access entry present (API mode)."
      ;;
    *)
      echo "--- aws-auth mapRoles after ensure ---"
      kubectl get configmap aws-auth -n kube-system -o jsonpath='{.data.mapRoles}' 2>/dev/null || true
      echo ""
      if ! kubectl get configmap aws-auth -n kube-system -o yaml | grep -Fq "${node_role_arn}"; then
        echo "::error::Node role ${node_role_arn} not found in aws-auth mapRoles."
        return 1
      fi
      echo "aws-auth mapRoles contains node role."
      ;;
  esac
}

apply_aws_auth_node_role_target() {
  local dev_abs="${1:-environments/dev}"
  local did_pushd=false

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars

  if ! eks_cluster_exists_in_aws "$(eks_cluster_name)"; then
    return 0
  fi

  ensure_node_cluster_auth_for_dev

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  mapfile -t var_args < <(tf_var_args)
  mapfile -t dev_args < <(tf_dev_extra_var_args)

  echo "Recording aws-auth merge in Terraform state (targeted)..."
  terraform apply -input=false -auto-approve -no-color \
    "${var_args[@]}" "${dev_args[@]}" \
    -target='module.eks.null_resource.aws_auth_node_role[0]'

  [ "${did_pushd}" = true ] && popd >/dev/null
}

# Print node join hints when a node group is CREATE_FAILED.
diagnose_node_join_failure() {
  tf_export_dev_vars
  local cluster_name="${1:-$(eks_cluster_name)}"
  local nodegroup_name="${2:-general}"

  echo "=== Node join diagnostics (${cluster_name}/${nodegroup_name}) ==="
  aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.{authMode:accessConfig.authenticationMode,publicEndpoint:resourcesVpcConfig.endpointPublicAccess}' \
    --output json 2>/dev/null || true

  local node_role_arn
  node_role_arn="$(node_iam_role_arn "${cluster_name}" 2>/dev/null || echo "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${cluster_name}-node")"
  local auth_mode
  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text 2>/dev/null || echo "unknown")"

  echo "--- access entry for node role (required for API mode; must be absent for API_AND_CONFIG_MAP) ---"
  if aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${AWS_REGION}" &>/dev/null; then
    aws eks describe-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${AWS_REGION}" \
      --output json 2>/dev/null || true
    if [ "${auth_mode}" = "API_AND_CONFIG_MAP" ]; then
      echo "::error::Node access entry present in API_AND_CONFIG_MAP — API auth is tried first and often causes Unauthorized."
    fi
    echo "--- associated access policies for node role ---"
    aws eks list-associated-access-policies \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${AWS_REGION}" \
      --output json 2>/dev/null || echo "(none or could not list)"
    if [ "${auth_mode}" = "API" ] && ! aws eks list-associated-access-policies \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${AWS_REGION}" \
      --query "associatedAccessPolicies[?policyArn=='arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodegroupPolicy']" \
      --output text 2>/dev/null | grep -q AmazonEKSNodegroupPolicy; then
      echo "::error::AmazonEKSNodegroupPolicy not associated — nodes stay Unauthorized in API mode."
    fi
  else
    if [ "${auth_mode}" = "API" ]; then
      echo "::error::Node access entry missing — API mode requires EC2_LINUX entry for the node role."
    else
      echo "(no access entry for node role — expected for API_AND_CONFIG_MAP + aws-auth)"
    fi
  fi

  if [ "${auth_mode}" != "API" ]; then
    echo "--- aws-auth mapRoles (node role should appear here) ---"
    aws eks update-kubeconfig --name "${cluster_name}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
    kubectl get configmap aws-auth -n kube-system -o jsonpath='{.data.mapRoles}' 2>/dev/null \
      || echo "(could not read aws-auth)"
  fi

  aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.{status:status,nodeRole:nodeRole,launchTemplate:launchTemplate,health:health,resources:resources}' \
    --output json 2>/dev/null || true

  local asg_name
  asg_name="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.resources.autoScalingGroups[0].name' \
    --output text 2>/dev/null || true)"

  if [ -n "${asg_name}" ] && [ "${asg_name}" != "None" ]; then
    aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "${asg_name}" \
      --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
      --output text 2>/dev/null | tr '\t' '\n' | while read -r iid; do
        [ -z "${iid}" ] || [ "${iid}" = "None" ] && continue
        echo "--- instance IAM profile (EC2 API): ${iid} ---"
        local profile_arn private_dns
        profile_arn="$(aws ec2 describe-instances --instance-ids "${iid}" --region "${AWS_REGION}" \
          --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text 2>/dev/null || echo "None")"
        private_dns="$(aws ec2 describe-instances --instance-ids "${iid}" --region "${AWS_REGION}" \
          --query 'Reservations[0].Instances[0].PrivateDnsName' --output text 2>/dev/null || echo "None")"
        echo "IamInstanceProfile=${profile_arn}"
        echo "PrivateDnsName=${private_dns}"
        if [ -z "${profile_arn}" ] || [ "${profile_arn}" = "None" ]; then
          echo "::error::No IAM instance profile on instance — kubelet has no AWS credentials (shows as Unauthorized)."
        fi
        echo "--- console output: ${iid} (last 80 lines) ---"
        aws ec2 get-console-output --instance-id "${iid}" --region "${AWS_REGION}" \
          --query 'Output' --output text 2>/dev/null | tail -80 || true
        if aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=${iid}" \
          --query 'InstanceInformationList[0].PingStatus' \
          --output text 2>/dev/null | grep -q Online; then
          echo "--- instance IAM role (IMDSv2): ${iid} ---"
          aws ssm send-command \
            --instance-ids "${iid}" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H \"X-aws-ec2-metadata-token-ttl-seconds: 60\"); ROLE=$(curl -s -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/iam/security-credentials/ | head -1); echo role=$ROLE"]' \
            --region "${AWS_REGION}" \
            --output text --query 'Command.CommandId' 2>/dev/null | while read -r cmd_id; do
              sleep 8
              aws ssm get-command-invocation \
                --command-id "${cmd_id}" \
                --instance-id "${iid}" \
                --region "${AWS_REGION}" \
                --query 'StandardOutputContent' \
                --output text 2>/dev/null || true
            done
          echo "--- kubelet journal: ${iid} (last 40 lines) ---"
          aws ssm send-command \
            --instance-ids "${iid}" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["journalctl -u kubelet --no-pager -n 40 2>/dev/null || true"]' \
            --region "${AWS_REGION}" \
            --output text --query 'Command.CommandId' 2>/dev/null | while read -r cmd_id; do
              sleep 8
              aws ssm get-command-invocation \
                --command-id "${cmd_id}" \
                --instance-id "${iid}" \
                --region "${AWS_REGION}" \
                --query 'StandardOutputContent' \
                --output text 2>/dev/null || true
            done
        fi
      done
  fi
}

# Scale down / delete node group before terraform destroy (faster, fewer timeouts).
dev_stack_destroy_prep() {
  tf_export_dev_vars
  local cluster_name nodegroup_name status
  cluster_name="$(eks_cluster_name)"
  nodegroup_name="general"

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    echo "EKS cluster ${cluster_name} not found; skipping node group teardown."
    return 0
  fi

  if ! aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" &>/dev/null; then
    echo "Node group ${nodegroup_name} not found; skipping."
    return 0
  fi

  status="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.status' \
    --output text)"

  echo "Node group ${nodegroup_name} status=${status}; scaling to 0..."
  aws eks update-nodegroup-config \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --scaling-config "minSize=0,maxSize=0,desiredSize=0" 2>/dev/null || true

  if aws eks wait nodegroup-active \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" 2>/dev/null; then
    echo "Deleting node group ${nodegroup_name} before Terraform destroy..."
    aws eks delete-nodegroup \
      --cluster-name "${cluster_name}" \
      --nodegroup-name "${nodegroup_name}" \
      --region "${AWS_REGION}" || true
    aws eks wait nodegroup-deleted \
      --cluster-name "${cluster_name}" \
      --nodegroup-name "${nodegroup_name}" \
      --region "${AWS_REGION}" 2>/dev/null || true
  fi
}

bootstrap_destroy_var_args() {
  printf '%s\n' "-var=state_bucket_force_destroy=true"
}

terraform_state_lock_id() {
  printf '%s/%s' "${1:?}" "${2:?}"
}

terraform_state_digest_lock_id() {
  printf '%s/%s-md5' "${1:?}" "${2:?}"
}

delete_dynamodb_lock_id() {
  local table="$1"
  local lock_id="$2"
  if aws dynamodb delete-item \
    --table-name "${table}" \
    --region "${AWS_REGION}" \
    --key "{\"LockID\":{\"S\":\"${lock_id}\"}}" \
    --return-values ALL_OLD \
    --output json 2>/dev/null | grep -q LockID; then
    echo "  deleted LockID=${lock_id}"
    return 0
  fi
  return 1
}

# Terraform S3 backend stores digests at LockID "{bucket}/{key}-md5" (not found by generic scans on some IAM policies).
delete_terraform_state_lock_records() {
  local bucket="$1"
  local state_key="$2"
  local table="$3"
  delete_dynamodb_lock_id "${table}" "$(terraform_state_lock_id "${bucket}" "${state_key}")" || true
  delete_dynamodb_lock_id "${table}" "$(terraform_state_digest_lock_id "${bucket}" "${state_key}")" || true
}

# Write Digest in DynamoDB to match current S3 state object (fixes checksum mismatch after recovery).
sync_terraform_state_digest_from_s3() {
  local bucket="$1"
  local state_key="$2"
  local table="$3"
  local lock_id digest tmp

  if ! aws s3api head-object --bucket "${bucket}" --key "${state_key}" --region "${AWS_REGION}" &>/dev/null; then
    echo "::warning::Cannot sync digest; s3://${bucket}/${state_key} missing."
    return 1
  fi

  lock_id="$(terraform_state_digest_lock_id "${bucket}" "${state_key}")"
  tmp="$(mktemp)"
  aws s3 cp "s3://${bucket}/${state_key}" "${tmp}" --region "${AWS_REGION}" >/dev/null
  digest="$(md5sum "${tmp}" | awk '{print $1}')"
  rm -f "${tmp}"

  aws dynamodb put-item \
    --table-name "${table}" \
    --region "${AWS_REGION}" \
    --item "{\"LockID\":{\"S\":\"${lock_id}\"},\"Digest\":{\"S\":\"${digest}\"}}"

  echo "Synced DynamoDB digest for ${lock_id} -> ${digest}"
}

# Remove lock/digest rows for all state keys used in this repo.
clear_terraform_state_lock_table() {
  tf_common_vars
  local table="${TF_BACKEND_DYNAMODB_TABLE:-${TF_STATE_DYNAMODB_TABLE:-}}"
  local bucket="${TF_BACKEND_BUCKET:-}"
  local lock_id deleted=0

  if [ -z "${table}" ]; then
    table="${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-locks"
  fi
  if [ -z "${bucket}" ]; then
    bucket="$(bootstrap_state_bucket_name)"
  fi

  if ! aws dynamodb describe-table --table-name "${table}" --region "${AWS_REGION}" &>/dev/null; then
    echo "Lock table ${table} does not exist."
    return 0
  fi

  echo "Deleting Terraform state lock/digest rows for ${bucket}..."
  for state_key in \
    "global/bootstrap/terraform.tfstate" \
    "global/policies/terraform.tfstate" \
    "dev/terraform.tfstate"; do
    delete_terraform_state_lock_records "${bucket}" "${state_key}" "${table}"
  done

  echo "Scanning ${table} for remaining lock rows..."
  while read -r lock_id; do
    [ -z "${lock_id}" ] && continue
    if delete_dynamodb_lock_id "${table}" "${lock_id}"; then
      deleted=$((deleted + 1))
    fi
  done < <(aws dynamodb scan \
    --table-name "${table}" \
    --region "${AWS_REGION}" \
    --projection-expression "LockID" \
    --query 'Items[].LockID.S' \
    --output text 2>/dev/null | tr '\t' '\n')

  echo "Removed ${deleted} additional lock/digest record(s) from ${table}."
}

# After a bad empty-bucket step: restore minimal state object so init/destroy can proceed.
ensure_remote_state_object_exists() {
  local state_key="${1:?}"
  local bucket kms_arn

  resolve_bootstrap_backend_env "$(bootstrap_dir_abs global/bootstrap)"
  bucket="${TF_BACKEND_BUCKET}"
  kms_arn="${TF_STATE_KMS_KEY_ARN:-}"

  if aws s3api head-object --bucket "${bucket}" --key "${state_key}" --region "${AWS_REGION}" &>/dev/null; then
    echo "State object s3://${bucket}/${state_key} exists."
    return 0
  fi

  echo "Restoring placeholder state at s3://${bucket}/${state_key} (import will repopulate resources)..."
  local tmp
  tmp="$(mktemp)"
  printf '%s\n' \
    '{"version":4,"terraform_version":"1.7.5","serial":1,"lineage":"destroy-recovery","outputs":{},"resources":[]}' \
    >"${tmp}"
  if [ -n "${kms_arn}" ]; then
    aws s3 cp "${tmp}" "s3://${bucket}/${state_key}" \
      --region "${AWS_REGION}" \
      --sse aws:kms \
      --sse-kms-key-id "${kms_arn}"
  else
    aws s3 cp "${tmp}" "s3://${bucket}/${state_key}" \
      --region "${AWS_REGION}" \
      --sse AES256
  fi
  rm -f "${tmp}"
}

# Run before any terraform init on destroy (checksum mismatch when S3 state was wiped).
repair_remote_state_backend_for_destroy() {
  local table bucket state_key

  bootstrap_recover_kms || true
  resolve_bootstrap_backend_env "$(bootstrap_dir_abs global/bootstrap)"
  table="${TF_BACKEND_DYNAMODB_TABLE}"
  bucket="${TF_BACKEND_BUCKET}"
  clear_s3_state_lockfiles "${bucket}"
  clear_terraform_state_lock_table

  for state_key in \
    "global/bootstrap/terraform.tfstate" \
    "global/policies/terraform.tfstate" \
    "dev/terraform.tfstate"; do
    ensure_remote_state_object_exists "${state_key}" || true
    if aws s3api head-object --bucket "${bucket}" --key "${state_key}" --region "${AWS_REGION}" &>/dev/null; then
      sync_terraform_state_digest_from_s3 "${bucket}" "${state_key}" "${table}" || true
    fi
  done
}

# After dev/policies destroy, drop their state objects so bootstrap can delete the bucket.
remove_downstream_remote_state_keys() {
  resolve_bootstrap_backend_env "$(bootstrap_dir_abs global/bootstrap)" || return 0
  local bucket="${TF_BACKEND_BUCKET}"

  if ! aws s3api head-bucket --bucket "${bucket}" --region "${AWS_REGION}" 2>/dev/null; then
    return 0
  fi

  echo "Removing dev/policies state objects from ${bucket} (bootstrap state kept for destroy)..."
  bootstrap_delete_s3_object_all_versions "${bucket}" "dev/terraform.tfstate"
  bootstrap_delete_s3_object_all_versions "${bucket}" "global/policies/terraform.tfstate"
  bootstrap_delete_s3_object_all_versions "${bucket}" "dev/terraform.tfstate.tflock"
  bootstrap_delete_s3_object_all_versions "${bucket}" "global/policies/terraform.tfstate.tflock"
  delete_terraform_state_lock_records "${bucket}" "dev/terraform.tfstate" "${TF_BACKEND_DYNAMODB_TABLE}"
  delete_terraform_state_lock_records "${bucket}" "global/policies/terraform.tfstate" "${TF_BACKEND_DYNAMODB_TABLE}"
  clear_s3_state_lockfiles "${bucket}"
}

prepare_bootstrap_destroy() {
  local bootstrap_abs
  bootstrap_abs="$(bootstrap_dir_abs global/bootstrap)"
  bootstrap_recover_kms || true
  repair_remote_state_backend_for_destroy
  bootstrap_init "${bootstrap_abs}"
  echo "Importing bootstrap resources into state (recovery after partial destroy)..."
  import_existing_bootstrap_resources "${bootstrap_abs}"
}

# Destroy bootstrap with safe ordering: cancel KMS deletion, drop dependents, then bucket/KMS.
bootstrap_terraform_destroy() {
  local bootstrap_dir="${1:-global/bootstrap}"
  local bootstrap_abs bucket rc
  bootstrap_abs="$(bootstrap_dir_abs "${bootstrap_dir}")"
  bucket="$(bootstrap_state_bucket_name)"

  bootstrap_recover_kms || true
  clear_s3_state_lockfiles "${bucket}"

  pushd "${bootstrap_abs}" >/dev/null
  mapfile -t var_args < <(tf_var_args)
  mapfile -t destroy_args < <(bootstrap_destroy_var_args)
  mapfile -t state_args < <(bootstrap_local_state_args)

  for target in \
    aws_dynamodb_table.terraform_state_lock \
    aws_s3_bucket_versioning.terraform_state \
    aws_s3_bucket_server_side_encryption_configuration.terraform_state \
    aws_s3_bucket_public_access_block.terraform_state; do
    echo "Destroying ${target} before bucket/KMS..."
    terraform destroy -input=false -auto-approve -no-color \
      -target="${target}" \
      "${state_args[@]}" "${var_args[@]}" "${destroy_args[@]}" || true
  done

  bootstrap_recover_kms || true

  terraform destroy -input=false -auto-approve -no-color \
    "${state_args[@]}" "${var_args[@]}" "${destroy_args[@]}"
  rc=$?

  if [ "${rc}" -ne 0 ]; then
    echo "::warning::Bootstrap destroy failed (exit ${rc}); attempting KMS recovery and bucket cleanup."
    bootstrap_recover_kms || true
    clear_s3_state_lockfiles "${bucket}"
    if bootstrap_state_bucket_exists; then
      bootstrap_empty_state_bucket_all_versions "${bucket}"
      bootstrap_recover_kms || true
      terraform destroy -input=false -auto-approve -no-color \
        "${state_args[@]}" "${var_args[@]}" "${destroy_args[@]}" || rc=$?
    fi
  fi

  popd >/dev/null
  return "${rc}"
}

# Final cleanup when bucket or KMS alias remain after destroy.
bootstrap_post_destroy_cleanup() {
  local bucket kms_alias

  bootstrap_recover_kms || true
  bucket="$(bootstrap_state_bucket_name)"
  if bootstrap_state_bucket_exists; then
    echo "State bucket still exists; removing all versioned objects..."
    bootstrap_empty_state_bucket_all_versions "${bucket}"
    aws s3api delete-bucket --bucket "${bucket}" --region "${AWS_REGION}" 2>/dev/null \
      && echo "Deleted bucket ${bucket}." \
      || echo "::warning::Could not delete bucket ${bucket}; delete manually." >&2
  fi
  kms_alias="$(bootstrap_kms_alias_name)"
  if bootstrap_kms_alias_exists; then
    aws kms delete-alias --alias-name "${kms_alias}" --region "${AWS_REGION}" 2>/dev/null || true
  fi
}

# Prepare dev stack before plan/apply (init + cluster recovery + auth mode).
dev_stack_prepare() {
  local dev_abs="${1:-environments/dev}"
  recover_eks_cluster_before_apply "${dev_abs}"
  upgrade_eks_authentication_mode_if_needed
  migrate_dev_cluster_to_api_node_auth
  import_eks_node_access_to_state "${dev_abs}"
  cleanup_stale_eks_auth_state "${dev_abs}"
  apply_eks_public_endpoint_if_needed "${dev_abs}"
  reset_stale_eks_managed_nodegroup
  apply_aws_auth_node_role_target "${dev_abs}"
  delete_failed_eks_node_groups "${dev_abs}"
}

# Import dev/EKS resources that exist in AWS but are missing from state (partial apply recovery).
import_existing_dev_resources() {
  local dev_abs="${1:-environments/dev}"
  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars

  local cluster_name
  cluster_name="$(eks_cluster_name)"
  local node_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${cluster_name}-node"
  local log_group_name="/aws/eks/${cluster_name}/cluster"
  local nodegroup_name="general"

  pushd "${dev_abs}" >/dev/null
  mapfile -t var_args < <(tf_var_args)
  mapfile -t dev_args < <(tf_dev_extra_var_args)

  terraform_state_has() {
    terraform state show -no-color "$1" &>/dev/null
  }

  import_if_missing() {
    local addr="$1"
    local id="$2"
    local optional="${3:-false}"

    if terraform_state_has "${addr}"; then
      return 0
    fi

    echo "Importing existing dev resource ${addr}..."
    if terraform import -input=false "${var_args[@]}" "${dev_args[@]}" "${addr}" "${id}"; then
      return 0
    fi

    if [ "${optional}" = "true" ]; then
      echo "::warning::Could not import ${addr}; Terraform will create or update it on apply."
      return 0
    fi

    return 1
  }

  if aws logs describe-log-groups --log-group-name-prefix "${log_group_name}" \
    --query "logGroups[?logGroupName=='${log_group_name}'] | length(@)" --output text 2>/dev/null | grep -q '^1$'; then
    import_if_missing module.eks.aws_cloudwatch_log_group.cluster "${log_group_name}" true
  fi

  local oidc_issuer oidc_provider_arn
  oidc_issuer="$(aws eks describe-cluster --name "${cluster_name}" --region "${AWS_REGION}" --query 'cluster.identity.oidc.issuer' --output text)"
  if [ -n "${oidc_issuer}" ] && [ "${oidc_issuer}" != "None" ]; then
    oidc_provider_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${oidc_issuer#https://}"
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${oidc_provider_arn}" &>/dev/null; then
      import_if_missing module.eks.aws_iam_openid_connect_provider.cluster "${oidc_provider_arn}" true
    fi
  fi

  import_if_missing "module.eks.aws_eks_addon.vpc_cni" "${cluster_name}:vpc-cni" true

  if aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${AWS_REGION}" &>/dev/null; then
    import_if_missing "module.eks.aws_eks_access_entry.node[0]" "${cluster_name}:${node_role_arn}" true
  fi

  local nodegroup_policy_arn="arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodegroupPolicy"
  if aws eks list-associated-access-policies \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${AWS_REGION}" \
    --query "associatedAccessPolicies[?policyArn=='${nodegroup_policy_arn}'].policyArn | [0]" \
    --output text 2>/dev/null | grep -q "${nodegroup_policy_arn}"; then
    import_if_missing \
      "module.eks.aws_eks_access_policy_association.node[0]" \
      "${cluster_name}#${node_role_arn}#${nodegroup_policy_arn}" \
      true
  fi

  local addon_name addon_addr
  for addon_name in kube-proxy coredns aws-ebs-csi-driver; do
    case "${addon_name}" in
      kube-proxy) addon_addr="module.addons.aws_eks_addon.kube_proxy" ;;
      coredns) addon_addr="module.addons.aws_eks_addon.coredns" ;;
      aws-ebs-csi-driver) addon_addr="module.addons.aws_eks_addon.aws_ebs_csi_driver" ;;
    esac
    if aws eks describe-addon \
      --cluster-name "${cluster_name}" \
      --addon-name "${addon_name}" \
      --region "${AWS_REGION}" &>/dev/null; then
      import_if_missing "${addon_addr}" "${cluster_name}:${addon_name}" true
    fi
  done

  if aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" &>/dev/null; then
    import_if_missing \
      "module.eks.aws_eks_node_group.main[\"${nodegroup_name}\"]" \
      "${cluster_name}:${nodegroup_name}" \
      true
  fi

  popd >/dev/null
}
