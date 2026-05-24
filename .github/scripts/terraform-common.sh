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
  : "${TF_STATE_KMS_KEY_ARN:?Set TF_STATE_KMS_KEY_ARN (bootstrap output kms_key_arn)}"
  : "${TF_BACKEND_BUCKET:?Set TF_BACKEND_BUCKET or TF_STATE_BUCKET (bootstrap state bucket)}"

  export TF_VAR_state_kms_key_arn="${TF_STATE_KMS_KEY_ARN}"
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
  terraform state list -no-color 2>/dev/null | grep -Fxq "${cluster_addr}"
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

# Import or re-import the cluster when AWS has it but Terraform plans to create it.
recover_eks_cluster_before_apply() {
  local dev_dir="${1:-environments/dev}"
  local cluster_name cluster_addr
  local import_status=0

  tf_export_dev_vars
  tf_init_s3_backend "${dev_dir}" dev/terraform.tfstate
  cluster_name="$(eks_cluster_name)"
  cluster_addr="module.eks.aws_eks_cluster.main"

  pushd "${dev_dir}" >/dev/null

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    echo "EKS cluster ${cluster_name} not in AWS; apply will create it."
    popd >/dev/null
    return 0
  fi

  if eks_cluster_in_state "${cluster_addr}" && ! eks_cluster_plan_wants_recreate "${cluster_addr}"; then
    echo "${cluster_addr} is in state and plan does not recreate it; OK to apply."
    popd >/dev/null
    return 0
  fi

  if eks_cluster_in_state "${cluster_addr}" && eks_cluster_plan_wants_recreate "${cluster_addr}"; then
    echo "::error::${cluster_addr} is in state but plan wants to create/replace the cluster (config drift)."
    echo "::error::Common causes: access_config authentication_mode change or cluster version mismatch."
    echo "::error::This module omits access_config by default on imports. Pull latest main and re-run apply."
    terraform plan -input=false -no-color || true
    popd >/dev/null
    return 1
  fi

  if eks_cluster_in_state "${cluster_addr}"; then
    echo "::warning::${cluster_addr} is in state but plan wants recreate; re-importing."
    terraform state rm -input=false "${cluster_addr}" || true
  else
    echo "${cluster_addr} missing from state but cluster exists in AWS; importing."
  fi

  echo "==> terraform import -target=${cluster_addr} ${cluster_addr} ${cluster_name}"
  set +e
  terraform import -input=false -target="${cluster_addr}" "${cluster_addr}" "${cluster_name}"
  import_status=$?
  set -e

  if [ "${import_status}" -ne 0 ]; then
    echo "::error::terraform import failed with status ${import_status}"
    dev_import_diagnostics "${dev_dir}"
    popd >/dev/null
    return 1
  fi

  if eks_cluster_plan_wants_recreate "${cluster_addr}"; then
    echo "::error::Plan still wants to create/replace ${cluster_addr} after import."
    terraform plan -input=false -no-color || true
    popd >/dev/null
    return 1
  fi

  echo "Cluster recovered in state; safe to apply."
  popd >/dev/null
}

# Print context when debugging import/state issues in CI.
dev_import_diagnostics() {
  local dev_dir="${1:-environments/dev}"
  local cluster_name

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
  aws sts get-caller-identity
  if eks_cluster_exists_in_aws "${cluster_name}"; then
    echo "AWS: cluster EXISTS (describe-cluster OK)"
  else
    echo "AWS: cluster NOT FOUND (describe-cluster failed)"
  fi

  pushd "${dev_dir}" >/dev/null
  if terraform state show -no-color module.eks.aws_eks_cluster.main &>/dev/null; then
    echo "Terraform state: module.eks.aws_eks_cluster.main is present"
  else
    echo "Terraform state: module.eks.aws_eks_cluster.main is MISSING"
  fi
  echo "EKS-related state addresses:"
  terraform state list -no-color 2>/dev/null | grep -E 'module\.eks|eks_cluster' || echo "(none)"
  popd >/dev/null
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

bootstrap_state_bucket_name() {
  tf_common_vars
  printf '%s\n' "${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-state-${AWS_ACCOUNT_ID}"
}

bootstrap_state_bucket_exists() {
  local bucket
  bucket="$(bootstrap_state_bucket_name)"
  aws s3api head-bucket --bucket "${bucket}" &>/dev/null
}

# True when bootstrap has not been migrated to S3 yet (first apply in this run).
bootstrap_uses_local_state() {
  [ -z "${TF_STATE_BUCKET:-}" ] && ! bootstrap_state_bucket_exists
}

# Emit -state=terraform.tfstate for plan/import/apply/output before S3 migration.
bootstrap_local_state_args() {
  if bootstrap_uses_local_state; then
    printf '%s\n' "-state=terraform.tfstate"
  fi
}

bootstrap_set_backend_from_aws() {
  tf_common_vars
  export TF_BACKEND_BUCKET
  TF_BACKEND_BUCKET="$(bootstrap_state_bucket_name)"
  export TF_BACKEND_DYNAMODB_TABLE="${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-locks"
  export TF_BACKEND_REGION="${AWS_REGION}"
  export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"

  local kms_alias="alias/${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-state"
  export TF_BACKEND_KMS_KEY_ID
  TF_BACKEND_KMS_KEY_ID="$(aws kms describe-key --key-id "${kms_alias}" --query 'KeyMetadata.KeyId' --output text)"
}

export_bootstrap_outputs() {
  local bootstrap_dir="${1:-global/bootstrap}"
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
  elif bootstrap_state_bucket_exists; then
    # Bootstrap was applied previously; use remote state even without TF_STATE_* vars.
    bootstrap_set_backend_from_aws
    mapfile -t backend_args < <(tf_backend_config_args)
    terraform init -input=false "${backend_args[@]}"
  else
    # Bucket does not exist yet; keep state local until maybe_migrate_bootstrap_state runs.
    terraform init -input=false -backend=false
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

# Import the EKS cluster into state when it already exists in AWS (required before apply).
ensure_eks_cluster_imported() {
  local dev_dir="${1:-environments/dev}"
  local dev_abs did_pushd=false
  local cluster_name cluster_addr

  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"
  cluster_addr="module.eks.aws_eks_cluster.main"

  dev_abs="$(cd "${dev_dir}" 2>/dev/null && pwd)" || {
    echo "::error::Dev directory not found: ${dev_dir}"
    return 1
  }

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
  if terraform import -input=false "${cluster_addr}" "${cluster_name}"; then
    terraform state show -no-color "${cluster_addr}" >/dev/null
    echo "Successfully imported ${cluster_addr}."
    if [ "${did_pushd}" = true ]; then
      popd >/dev/null
    fi
    return 0
  fi

  echo "::error::Cluster ${cluster_name} exists in AWS but Terraform import failed (see output above)."
  if [ "${did_pushd}" = true ]; then
    popd >/dev/null
  fi
  return 1
}

# Abort apply when the cluster exists in AWS but is still missing from state.
verify_eks_cluster_state() {
  local dev_dir="${1:-environments/dev}"
  local cluster_name cluster_addr

  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"
  cluster_addr="module.eks.aws_eks_cluster.main"

  pushd "${dev_dir}" >/dev/null

  if eks_cluster_exists_in_aws "${cluster_name}"; then
    if terraform state show -no-color "${cluster_addr}" &>/dev/null; then
      echo "Verified: ${cluster_name} is in AWS and Terraform state."
    else
      echo "::error::${cluster_name} exists in AWS but is not in Terraform state. Re-run import or run: terraform import ${cluster_addr} ${cluster_name}"
      popd >/dev/null
      return 1
    fi
  fi

  popd >/dev/null
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

# Prepare dev stack before plan/apply (init + cluster recovery + auth mode).
dev_stack_prepare() {
  recover_eks_cluster_before_apply "${1:-environments/dev}"
  upgrade_eks_authentication_mode_if_needed
}

# Import dev/EKS resources that exist in AWS but are missing from state (partial apply recovery).
import_existing_dev_resources() {
  local dev_dir="${1:-environments/dev}"
  tf_export_dev_vars

  local cluster_name
  cluster_name="$(eks_cluster_name)"
  local node_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${cluster_name}-node"
  local log_group_name="/aws/eks/${cluster_name}/cluster"
  local nodegroup_name="general"

  pushd "${dev_dir}" >/dev/null
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

  if aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${AWS_REGION}" &>/dev/null; then
    import_if_missing module.eks.aws_eks_access_entry.node "${cluster_name}:${node_role_arn}" true
    import_if_missing \
      module.eks.aws_eks_access_policy_association.node \
      "${cluster_name}#${node_role_arn}#arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodegroupPolicy" \
      true
  fi

  if aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" &>/dev/null; then
    import_if_missing \
      "module.eks.aws_eks_node_group.main[\"${nodegroup_name}\"]" \
      "${cluster_name}:${nodegroup_name}" \
      true

    local launch_template_id
    launch_template_id="$(aws eks describe-nodegroup \
      --cluster-name "${cluster_name}" \
      --nodegroup-name "${nodegroup_name}" \
      --query 'nodegroup.launchTemplate.id' \
      --output text)"
    if [ -n "${launch_template_id}" ] && [ "${launch_template_id}" != "None" ]; then
      import_if_missing \
        "module.eks.aws_launch_template.node_group[\"${nodegroup_name}\"]" \
        "${launch_template_id}" \
        true
    fi
  fi

  popd >/dev/null
}
