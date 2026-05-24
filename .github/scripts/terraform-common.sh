#!/usr/bin/env bash
# Shared helpers for Terraform in GitHub Actions and local use.
set -euo pipefail

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
  : "${TF_STATE_KMS_KEY_ARN:?Set TF_STATE_KMS_KEY_ARN (bootstrap output kms_key_arn)}"
  printf '%s\n' \
    "-var=state_kms_key_arn=${TF_STATE_KMS_KEY_ARN}" \
    "-var=state_bucket_name=${TF_BACKEND_BUCKET:-}" \
    "-var=state_kms_key_id=${TF_BACKEND_KMS_KEY_ID:-}" \
    "-var=dynamodb_table_name=${TF_BACKEND_DYNAMODB_TABLE:-}"
}

tf_backend_config_args() {
  : "${TF_BACKEND_BUCKET:?Set TF_BACKEND_BUCKET}"
  : "${TF_BACKEND_KMS_KEY_ID:?Set TF_BACKEND_KMS_KEY_ID}"
  : "${TF_BACKEND_DYNAMODB_TABLE:?Set TF_BACKEND_DYNAMODB_TABLE}"
  : "${TF_BACKEND_REGION:?Set TF_BACKEND_REGION}"

  printf '%s\n' \
    "-backend-config=bucket=${TF_BACKEND_BUCKET}" \
    "-backend-config=key=${TF_BACKEND_KEY}" \
    "-backend-config=region=${TF_BACKEND_REGION}" \
    "-backend-config=kms_key_id=${TF_BACKEND_KMS_KEY_ID}" \
    "-backend-config=dynamodb_table=${TF_BACKEND_DYNAMODB_TABLE}" \
    "-backend-config=encrypt=true"
}

export_bootstrap_outputs() {
  local bootstrap_dir="${1:-global/bootstrap}"
  pushd "${bootstrap_dir}" >/dev/null

  export TF_BACKEND_BUCKET
  TF_BACKEND_BUCKET="$(terraform output -raw state_bucket_name)"
  export TF_BACKEND_KMS_KEY_ID
  TF_BACKEND_KMS_KEY_ID="$(terraform output -raw kms_key_id)"
  export TF_BACKEND_DYNAMODB_TABLE
  TF_BACKEND_DYNAMODB_TABLE="$(terraform output -raw dynamodb_table_name)"
  export TF_STATE_KMS_KEY_ARN
  TF_STATE_KMS_KEY_ARN="$(terraform output -raw kms_key_arn)"
  export TF_BACKEND_REGION="${AWS_REGION}"

  popd >/dev/null
}

tf_init_s3_backend() {
  local dir="$1"
  local state_key="$2"
  pushd "${dir}" >/dev/null
  export TF_BACKEND_KEY="${state_key}"
  mapfile -t backend_args < <(tf_backend_config_args)
  terraform init -input=false "${backend_args[@]}"
  popd >/dev/null
}

maybe_migrate_bootstrap_state() {
  local bootstrap_dir="${1:-global/bootstrap}"

  if [ -n "${TF_STATE_BUCKET:-}" ]; then
    return 0
  fi

  export_bootstrap_outputs "${bootstrap_dir}"
  pushd "${bootstrap_dir}" >/dev/null
  export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"
  mapfile -t backend_args < <(tf_backend_config_args)
  terraform init -input=false -migrate-state -force-copy "${backend_args[@]}"
  popd >/dev/null
}

bootstrap_init() {
  local bootstrap_dir="${1:-global/bootstrap}"
  pushd "${bootstrap_dir}" >/dev/null

  if [ -n "${TF_STATE_BUCKET:-}" ]; then
    export TF_BACKEND_BUCKET="${TF_STATE_BUCKET}"
    export TF_BACKEND_KMS_KEY_ID="${TF_STATE_KMS_KEY_ID}"
    export TF_BACKEND_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE}"
    export TF_BACKEND_REGION="${AWS_REGION}"
    export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"
    mapfile -t backend_args < <(tf_backend_config_args)
    terraform init -input=false "${backend_args[@]}"
  else
    terraform init -input=false
  fi

  popd >/dev/null
}

# Import bootstrap resources that already exist in AWS but are missing from state
# (for example after a partial apply or lost local state before S3 migration).
import_existing_bootstrap_resources() {
  local bootstrap_dir="${1:-global/bootstrap}"
  tf_common_vars

  local name_prefix="${TF_PROJECT_NAME}-${TF_ENVIRONMENT}"
  local state_bucket="${name_prefix}-terraform-state-${AWS_ACCOUNT_ID}"
  local dynamodb_table="${name_prefix}-terraform-locks"
  local kms_alias="alias/${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-state"

  pushd "${bootstrap_dir}" >/dev/null
  mapfile -t var_args < <(tf_var_args)

  terraform_state_has() {
    terraform state show -no-color "$1" &>/dev/null
  }

  import_if_missing() {
    local addr="$1"
    local id="$2"

    if terraform_state_has "${addr}"; then
      return 0
    fi

    echo "Importing existing bootstrap resource ${addr}..."
    terraform import -input=false "${var_args[@]}" "${addr}" "${id}"
  }

  if aws kms describe-key --key-id "${kms_alias}" &>/dev/null; then
    local key_id
    key_id="$(aws kms describe-key --key-id "${kms_alias}" --query 'KeyMetadata.KeyId' --output text)"
    import_if_missing aws_kms_key.terraform_state "${key_id}"
    import_if_missing aws_kms_alias.terraform_state "${kms_alias}"
  fi

  if aws s3api head-bucket --bucket "${state_bucket}" &>/dev/null; then
    import_if_missing aws_s3_bucket.terraform_state "${state_bucket}"
    import_if_missing aws_s3_bucket_versioning.terraform_state "${state_bucket}"
    import_if_missing aws_s3_bucket_server_side_encryption_configuration.terraform_state "${state_bucket}"
    import_if_missing aws_s3_bucket_public_access_block.terraform_state "${state_bucket}"
  fi

  if aws dynamodb describe-table --table-name "${dynamodb_table}" &>/dev/null; then
    import_if_missing aws_dynamodb_table.terraform_state_lock "${dynamodb_table}"
  fi

  popd >/dev/null
}
