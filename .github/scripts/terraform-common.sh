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
    "-var=enable_eks=${TF_VAR_enable_eks:-false}" \
    "-var=enable_eks_cluster=${TF_VAR_enable_eks_cluster:-false}" \
    "-var=enable_eks_nodes=${TF_VAR_enable_eks_nodes:-false}" \
    "-var=enable_irsa=${TF_VAR_enable_irsa:-false}" \
    "-var=enable_addons=${TF_VAR_enable_addons:-false}" \
    "-var=state_kms_key_arn=${TF_VAR_state_kms_key_arn}" \
    "-var=state_bucket_name=${TF_VAR_state_bucket_name}" \
    "-var=state_kms_key_id=${TF_VAR_state_kms_key_id}" \
    "-var=dynamodb_table_name=${TF_VAR_dynamodb_table_name}"
}

_tf_bool_is_true() {
  case "${1:-false}" in
    true | True | TRUE | 1 | yes | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Map workflow dev_eks_phase to TF_VAR_enable_* (cumulative phases).
apply_dev_eks_phase_from_input() {
  local phase="${1:-none}"

  export TF_VAR_enable_eks=false
  export TF_VAR_enable_eks_cluster=false
  export TF_VAR_enable_eks_nodes=false
  export TF_VAR_enable_irsa=false
  export TF_VAR_enable_addons=false

  case "${phase}" in
    all)
      export TF_VAR_enable_eks=true
      ;;
    cluster)
      export TF_VAR_enable_eks_cluster=true
      ;;
    nodes)
      export TF_VAR_enable_eks_cluster=true
      export TF_VAR_enable_eks_nodes=true
      ;;
    irsa)
      export TF_VAR_enable_eks_cluster=true
      export TF_VAR_enable_eks_nodes=true
      export TF_VAR_enable_irsa=true
      ;;
    addons|addons-only)
      export TF_VAR_enable_eks_cluster=true
      export TF_VAR_enable_eks_nodes=true
      export TF_VAR_enable_irsa=true
      export TF_VAR_enable_addons=true
      ;;
    none | foundation | "")
      ;;
    *)
      echo "::error::Unknown dev_eks_phase: ${phase} (use none, cluster, nodes, irsa, addons, addons-only, or all)" >&2
      return 1
      ;;
  esac

  echo "Dev EKS phase: ${phase} → cluster=${TF_VAR_enable_eks_cluster} nodes=${TF_VAR_enable_eks_nodes} irsa=${TF_VAR_enable_irsa} addons=${TF_VAR_enable_addons} (enable_eks=${TF_VAR_enable_eks})"
}

dev_stack_enable_eks_cluster() {
  _tf_bool_is_true "${TF_VAR_enable_eks:-false}" && return 0
  _tf_bool_is_true "${TF_VAR_enable_eks_cluster:-false}" && return 0
  _tf_bool_is_true "${TF_VAR_enable_eks_nodes:-false}" && return 0
  _tf_bool_is_true "${TF_VAR_enable_irsa:-false}" && return 0
  _tf_bool_is_true "${TF_VAR_enable_addons:-false}" && return 0
  return 1
}

dev_stack_enable_eks_nodes() {
  _tf_bool_is_true "${TF_VAR_enable_eks:-false}" && return 0
  _tf_bool_is_true "${TF_VAR_enable_eks_nodes:-false}" && return 0
  _tf_bool_is_true "${TF_VAR_enable_irsa:-false}" && return 0
  _tf_bool_is_true "${TF_VAR_enable_addons:-false}" && return 0
  return 1
}

# Any EKS phase beyond foundation (VPC/IAM/SG).
dev_stack_enable_eks() {
  dev_stack_enable_eks_cluster
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

# environments/dev uses count on module "eks" (addresses are module.eks[0].*).
dev_eks_state_prefix() {
  printf '%s' 'module.eks[0]'
}

dev_addons_state_prefix() {
  printf '%s' 'module.addons[0]'
}

dev_stack_enable_addons() {
  _tf_bool_is_true "${TF_VAR_enable_eks:-false}" && return 0
  _tf_bool_is_true "${TF_VAR_enable_addons:-false}" && return 0
  return 1
}

# Print EKS add-on install/destroy order and current AWS status (CI log).
log_eks_addon_lifecycle() {
  local operation="${1:-apply}"
  local cluster_name

  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"

  echo ""
  echo "=== EKS add-on lifecycle order (${cluster_name}) ==="
  echo "Operation context: ${operation}"
  echo ""
  echo "Full platform order (dev_eks_phase cumulative):"
  echo "  1. [cluster]  vpc-cni                 → module.eks/aws_eks_addon.vpc_cni (before node groups)"
  echo "  2. [nodes]    managed node group      → module.eks/aws_eks_node_group (requires vpc-cni + Ready)"
  echo "  3. [irsa]     IAM roles for SA        → module.iam_irsa (vpc-cni aws-node, ebs-csi-controller-sa)"
  echo "  4. [addons]   kube-proxy              → module.addons/aws_eks_addon.kube_proxy (after nodes Ready)"
  echo "  5. [addons]   coredns                 → module.addons/aws_eks_addon.coredns (after kube-proxy)"
  echo "  6. [addons]   aws-ebs-csi-driver      → module.addons/aws_eks_addon.aws_ebs_csi_driver (after kube-proxy + ebs-csi IRSA)"
  echo ""
  echo "module.addons Terraform CREATE order:"
  echo "  (1) kube-proxy"
  echo "  (2) coredns + aws-ebs-csi-driver   ← parallel after kube-proxy"
  echo ""
  echo "module.addons Terraform DESTROY order (reverse dependencies):"
  echo "  (1) coredns + aws-ebs-csi-driver"
  echo "  (2) kube-proxy"
  echo ""
  echo "Note: vpc-cni lives in module.eks; it is NOT destroyed when recreating module.addons only."
  echo ""

  case "${operation}" in
    destroy|recreate)
      echo "Addons-only destroy/recreate (keeps cluster + nodes) — run from environments/dev after init:"
      echo "  terraform destroy \\"
      echo "    -target='$(dev_addons_state_prefix).aws_eks_addon.coredns' \\"
      echo "    -target='$(dev_addons_state_prefix).aws_eks_addon.aws_ebs_csi_driver' \\"
      echo "    -target='$(dev_addons_state_prefix).aws_eks_addon.kube_proxy'"
      echo "  terraform apply   # dev_eks_phase: addons (or enable_irsa + enable_addons=true)"
      echo ""
      echo "GitHub Actions full destroy (dev_eks_phase: addons) removes cluster, nodes, IRSA, VPC, and add-ons."
      echo "  → To destroy add-ons ONLY, use dev_eks_phase: addons-only (not addons)."
      ;;
    apply)
      echo "GitHub Actions: dev_eks_phase=addons (or addons-only) runs IRSA then creates add-ons in order above."
      echo "  → dev_eks_phase=addons-only + destroy removes add-ons only; + apply recreates them."
      ;;
  esac

  log_eks_addon_aws_status "${cluster_name}"
}

# Current EKS managed add-on status from AWS (for CI logs).
log_eks_addon_aws_status() {
  local cluster_name="${1:-$(eks_cluster_name)}"
  local addon_name

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    echo "--- AWS EKS add-ons ---"
    echo "(cluster ${cluster_name} not found in AWS)"
    return 0
  fi

  echo "--- AWS EKS add-ons (cluster=${cluster_name}, region=${AWS_REGION}) ---"
  aws eks list-addons \
    --cluster-name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --output text 2>/dev/null || echo "(could not list add-ons)"

  for addon_name in vpc-cni kube-proxy coredns aws-ebs-csi-driver; do
    if aws eks describe-addon \
      --cluster-name "${cluster_name}" \
      --addon-name "${addon_name}" \
      --region "${AWS_REGION}" &>/dev/null; then
      aws eks describe-addon \
        --cluster-name "${cluster_name}" \
        --addon-name "${addon_name}" \
        --region "${AWS_REGION}" \
        --query 'addon.{name:addonName,status:status,version:addonVersion,health:health.issues}' \
        --output json 2>/dev/null \
        || echo "${addon_name}: (describe failed)"
    else
      echo "${addon_name}: (not installed)"
    fi
  done
  echo ""
}

# Remove module.addons only (keep cluster, nodes, IRSA, VPC). Uses enable_addons=false apply.
dev_destroy_addons_only() {
  local dev_abs="${1:-environments/dev}"
  local did_pushd=false

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  tf_init_s3_backend "${dev_abs}" dev/terraform.tfstate

  echo ""
  echo "=== Dev add-ons only destroy (cluster + nodes + VPC unchanged) ==="
  log_eks_addon_lifecycle destroy

  export TF_VAR_enable_eks=false
  export TF_VAR_enable_eks_cluster=true
  export TF_VAR_enable_eks_nodes=true
  export TF_VAR_enable_irsa=true
  export TF_VAR_enable_addons=false

  echo "Applying with enable_addons=false (module.addons count=0 destroys kube-proxy, coredns, aws-ebs-csi-driver)..."

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  mapfile -t var_args < <(tf_var_args)
  mapfile -t dev_args < <(tf_dev_extra_var_args)
  terraform apply -input=false -auto-approve -no-color "${var_args[@]}" "${dev_args[@]}"

  echo ""
  echo "Add-ons destroyed. Re-run apply with dev_eks_phase: addons-only (or addons) to recreate."
  log_eks_addon_aws_status "$(eks_cluster_name)"

  if [ "${did_pushd}" = true ]; then
    popd >/dev/null
  fi
}

dev_eks_cluster_state_addr() {
  printf '%s\n' "$(dev_eks_state_prefix).aws_eks_cluster.main"
}

eks_cluster_exists_in_aws() {
  local cluster_name="$1"
  aws eks describe-cluster --name "${cluster_name}" --region "${AWS_REGION}" &>/dev/null
}

eks_cluster_in_state() {
  local cluster_addr="${1:-$(dev_eks_cluster_state_addr)}"
  terraform state show -no-color "${cluster_addr}" &>/dev/null
}

# True when terraform plan wants to create or replace the EKS cluster (replace triggers CreateCluster → 409).
eks_cluster_plan_wants_recreate() {
  local cluster_addr="${1:-$(dev_eks_cluster_state_addr)}"
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
  cluster_addr="$(dev_eks_cluster_state_addr)"

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
  if terraform state show -no-color "$(dev_eks_cluster_state_addr)" &>/dev/null; then
    echo "Terraform state: $(dev_eks_cluster_state_addr) is present"
  else
    echo "Terraform state: $(dev_eks_cluster_state_addr) is MISSING"
  fi
  echo "EKS-related state addresses:"
  terraform state list -no-color 2>/dev/null | grep -E 'module\.eks|eks_cluster' || echo "(none)"
  [ "${did_pushd}" = true ] && popd >/dev/null
}

tf_backend_config_args() {
  local config_file="${1:-.terraform-backend.hcl}"
  bootstrap_write_backend_config_file "${config_file}"
  printf '%s\n' "-backend-config=${config_file}"
}

# Write backend.ci.hcl for terraform init (more reliable than many -backend-config flags on TF 1.7+).
bootstrap_write_backend_config_file() {
  local config_path="${1:-.terraform-backend.hcl}"

  : "${TF_BACKEND_BUCKET:?Set TF_BACKEND_BUCKET}"
  : "${TF_BACKEND_REGION:?Set TF_BACKEND_REGION}"
  : "${TF_BACKEND_KEY:?Set TF_BACKEND_KEY}"

  cat >"${config_path}" <<EOF
bucket       = "${TF_BACKEND_BUCKET}"
key          = "${TF_BACKEND_KEY}"
region       = "${TF_BACKEND_REGION}"
encrypt      = true
use_lockfile = true
EOF
  if [ -n "${TF_BACKEND_KMS_KEY_ID:-}" ]; then
    cat >>"${config_path}" <<EOF
kms_key_id   = "${TF_BACKEND_KMS_KEY_ID}"
EOF
  fi
  printf '%s\n' "${config_path}"
}

# True when terraform init configured the S3 backend (not provider-only init).
bootstrap_s3_backend_is_configured() {
  local meta=".terraform/terraform.tfstate"

  if [ -f "${meta}" ]; then
    if grep -qE '"type"[[:space:]]*:[[:space:]]*"s3"' "${meta}" 2>/dev/null \
      || grep -qE 'backend[[:space:]]+"s3"' "${meta}" 2>/dev/null \
      || grep -qE 'type[[:space:]]*=[[:space:]]*"s3"' "${meta}" 2>/dev/null; then
      return 0
    fi
  fi

  # Metadata layout varies by Terraform/AWS provider version; verify the CLI can reach state.
  terraform state list -no-color &>/dev/null
}

# Full S3 backend init for Terraform 1.7+ (clean .terraform + reconfigure + verify).
# Optional second argument: "migrate" runs -migrate-state -force-copy (local -> S3).
bootstrap_terraform_init_s3() {
  local mode="${1:-}"
  local config_path backend_arg
  local -a init_flags=(-input=false -upgrade)

  config_path="$(bootstrap_write_backend_config_file ".terraform-backend.hcl")"
  backend_arg="-backend-config=${config_path}"
  if [ "${mode}" = "migrate" ]; then
    # -migrate-state and -reconfigure are mutually exclusive (Terraform 1.7+).
    init_flags+=(-migrate-state -force-copy)
  else
    init_flags+=(-reconfigure)
  fi

  echo "Initializing S3 backend: s3://${TF_BACKEND_BUCKET}/${TF_BACKEND_KEY} (region ${TF_BACKEND_REGION})"
  rm -rf .terraform
  if ! terraform init "${init_flags[@]}" "${backend_arg}"; then
    echo "::error::terraform init failed for S3 backend. Check TF_BACKEND_* and AWS credentials." >&2
    return 1
  fi

  if ! bootstrap_s3_backend_is_configured; then
    echo "::error::terraform init succeeded but S3 backend is not usable (state list failed). Check TF_BACKEND_* and AWS credentials." >&2
    return 1
  fi
  echo "S3 backend configured."
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

bootstrap_state_s3_key() {
  printf '%s\n' "global/bootstrap/terraform.tfstate"
}

# Empty placeholder written by ensure_remote_state_object_exists (destroy recovery).
bootstrap_s3_state_is_placeholder() {
  local bucket="${1:-$(bootstrap_state_bucket_name)}"
  local key="${2:-$(bootstrap_state_s3_key)}"
  local tmp size

  if ! aws s3api head-object --bucket "${bucket}" --key "${key}" --region "${AWS_REGION}" &>/dev/null; then
    return 1
  fi

  size="$(aws s3api head-object --bucket "${bucket}" --key "${key}" \
    --region "${AWS_REGION}" --query 'ContentLength' --output text 2>/dev/null || true)"
  if [ -n "${size}" ] && [ "${size}" -lt 256 ]; then
    return 0
  fi
  if [ -n "${size}" ] && [ "${size}" -ge 256 ]; then
    return 1
  fi

  tmp="$(mktemp)"
  if ! aws s3 cp "s3://${bucket}/${key}" "${tmp}" \
    --region "${AWS_REGION}" --only-show-errors >/dev/null 2>&1; then
    rm -f "${tmp}"
    return 1
  fi
  if grep -q '"lineage":"destroy-recovery"' "${tmp}" 2>/dev/null \
    || grep -q '"resources":\[\]' "${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    return 0
  fi
  rm -f "${tmp}"
  return 1
}

# Remove invalid bootstrap state object so import/plan can repopulate from AWS.
bootstrap_clear_stale_s3_bootstrap_state() {
  local bucket key
  bucket="$(bootstrap_state_bucket_name)"
  key="$(bootstrap_state_s3_key)"

  if bootstrap_s3_state_is_placeholder "${bucket}" "${key}"; then
    echo "Removing placeholder bootstrap state at s3://${bucket}/${key}..." >&2
    aws s3api delete-object --bucket "${bucket}" --key "${key}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
    return 0
  fi

  if aws s3api head-object --bucket "${bucket}" --key "${key}" --region "${AWS_REGION}" &>/dev/null; then
    return 0
  fi
  return 1
}

# True when real bootstrap state (not empty placeholder) is in S3.
bootstrap_state_migrated_to_s3() {
  local bucket
  bucket="$(bootstrap_state_bucket_name)"
  bootstrap_state_bucket_exists \
    && aws s3api head-object \
      --bucket "${bucket}" \
      --key "$(bootstrap_state_s3_key)" \
      --region "${AWS_REGION}" &>/dev/null \
    && ! bootstrap_s3_state_is_placeholder "${bucket}" "$(bootstrap_state_s3_key)"
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

# Terraform 1.7+ init mode for bootstrap:
#   local      — no state bucket in AWS; swap backend.tf to backend "local" (S3 block breaks import)
#   partial_s3 — bucket exists but state object not in S3; init S3 with partial -backend-config
#   remote     — state object already in S3
bootstrap_init_mode() {
  if bootstrap_state_migrated_to_s3; then
    printf '%s\n' remote
  elif bootstrap_state_bucket_exists; then
    printf '%s\n' partial_s3
  else
    printf '%s\n' local
  fi
}

bootstrap_uses_local_state() {
  [ "$(bootstrap_init_mode)" = local ]
}

bootstrap_uses_partial_s3_backend() {
  [ "$(bootstrap_init_mode)" = partial_s3 ]
}

# Terraform 1.7+ cannot import/plan when backend.tf declares backend "s3" but init skipped S3.
# Swap to backend "local" in the workspace until maybe_migrate_bootstrap_state restores S3.
bootstrap_activate_local_backend_file() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  pushd "${bootstrap_dir}" >/dev/null
  if [ -f backend.tf.s3.workspace ]; then
    popd >/dev/null
    return 0
  fi
  if [ ! -f backend.tf ]; then
    echo "::error::global/bootstrap/backend.tf not found" >&2
    popd >/dev/null
    return 1
  fi
  cp -f backend.tf backend.tf.s3.workspace
  cat >backend.tf <<'EOF'
# Workspace copy for brand-new bootstrap (no state bucket yet). Restored after S3 migration.
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
  echo "Bootstrap: using backend \"local\" until state migrates to S3 (Terraform 1.7+ import/plan compat)." >&2
  popd >/dev/null
}

bootstrap_restore_s3_backend_file() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  pushd "${bootstrap_dir}" >/dev/null
  if [ -f backend.tf.s3.workspace ]; then
    mv -f backend.tf.s3.workspace backend.tf
    echo "Bootstrap: restored backend \"s3\" in backend.tf." >&2
  fi
  popd >/dev/null
}

bootstrap_init_local() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  echo "Bootstrap init: local state (state bucket does not exist yet)."
  bootstrap_activate_local_backend_file "${bootstrap_dir}"
  pushd "${bootstrap_dir}" >/dev/null
  rm -rf .terraform
  terraform init -input=false -reconfigure
  popd >/dev/null
}

bootstrap_init_partial_s3() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  echo "Bootstrap init: partial S3 backend (bucket exists; configuring S3 for import/plan/apply)." >&2
  bootstrap_clear_stale_s3_bootstrap_state || true
  bootstrap_restore_s3_backend_file "${bootstrap_dir}"
  pushd "${bootstrap_dir}" >/dev/null
  bootstrap_set_backend_for_existing_bucket
  bootstrap_terraform_init_s3
  popd >/dev/null
}

# No extra CLI args when backend "local" is active; default state path is terraform.tfstate.
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
  if ! bootstrap_export_reusable_kms_backend_env; then
    echo "::warning::Bootstrap KMS alias not reusable; remote backend may omit kms_key_id." >&2
    return 1
  fi
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

# Description string for the bootstrap CMK (must match global/bootstrap/main.tf).
bootstrap_kms_expected_description() {
  tf_common_vars
  printf 'Terraform remote state encryption for %s (%s)' \
    "${TF_PROJECT_NAME}" "${TF_ENVIRONMENT}"
}

# True only for CMKs created by this bootstrap module (not other workloads).
bootstrap_is_dedicated_bootstrap_kms_key() {
  local key_id="$1" desc expected

  [ -n "${key_id}" ] || return 1
  expected="$(bootstrap_kms_expected_description)"
  desc="$(aws kms describe-key --key-id "${key_id}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.Description' --output text 2>/dev/null || true)"
  [ "${desc}" = "${expected}" ]
}

# Find bootstrap CMK by description (any key state).
bootstrap_discover_dedicated_bootstrap_kms_key() {
  local key_id desc expected match=""

  expected="$(bootstrap_kms_expected_description)"
  while read -r key_id; do
    [ -z "${key_id}" ] && continue
    desc="$(aws kms describe-key --key-id "${key_id}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.Description' --output text 2>/dev/null || true)"
    if [ "${desc}" = "${expected}" ]; then
      match="${key_id}"
    fi
  done < <(aws kms list-keys --region "${AWS_REGION}" \
    --query 'Keys[].KeyId' --output text 2>/dev/null | tr '\t' '\n')

  if [ -n "${match}" ]; then
    printf '%s\n' "${match}"
    return 0
  fi
  return 1
}

# Find dedicated bootstrap CMK in PendingDeletion or Disabled only.
bootstrap_discover_unusable_bootstrap_kms_key() {
  local key_id state

  if ! key_id="$(bootstrap_discover_dedicated_bootstrap_kms_key 2>/dev/null)"; then
    return 1
  fi
  state="$(aws kms describe-key --key-id "${key_id}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.KeyState' --output text 2>/dev/null || true)"
  if [ "${state}" = "PendingDeletion" ] || [ "${state}" = "Disabled" ]; then
    printf '%s\n' "${key_id}"
    return 0
  fi
  return 1
}

bootstrap_discover_pending_bootstrap_kms_key() {
  bootstrap_discover_unusable_bootstrap_kms_key
}

bootstrap_kms_key_state() {
  local key_id="$1"
  aws kms describe-key --key-id "${key_id}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.KeyState' --output text 2>/dev/null || true
}

# Try to point bootstrap alias to a specific key.
# Returns:
#   0 = success
#   2 = access denied (caller should try next key)
#   1 = other error
bootstrap_try_bind_alias_to_key() {
  local key_id="$1" kms_alias target out rc

  kms_alias="$(bootstrap_kms_alias_name)"

  if bootstrap_kms_alias_exists; then
    target="$(aws kms describe-key --key-id "${kms_alias}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' --output text 2>/dev/null || true)"
    if [ "${target}" = "${key_id}" ]; then
      return 0
    fi
    out="$(aws kms update-alias \
      --alias-name "${kms_alias}" \
      --target-key-id "${key_id}" \
      --region "${AWS_REGION}" 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "${rc}" -eq 0 ]; then
      return 0
    fi
  else
    out="$(aws kms create-alias \
      --alias-name "${kms_alias}" \
      --target-key-id "${key_id}" \
      --region "${AWS_REGION}" 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "${rc}" -eq 0 ]; then
      return 0
    fi
  fi

  if [[ "${out}" == *"AccessDenied"* ]] || [[ "${out}" == *"AccessDeniedException"* ]]; then
    echo "Skipping key ${key_id}: alias permission denied for ${kms_alias}." >&2
    return 2
  fi

  echo "::warning::Failed binding alias ${kms_alias} to ${key_id}: ${out}" >&2
  return 1
}

# Return first Enabled KMS key in the account/region.
bootstrap_discover_any_enabled_kms_key() {
  local key_id state

  while read -r key_id; do
    [ -z "${key_id}" ] && continue
    state="$(bootstrap_kms_key_state "${key_id}")"
    if [ "${state}" = "Enabled" ]; then
      printf '%s\n' "${key_id}"
      return 0
    fi
  done < <(aws kms list-keys --region "${AWS_REGION}" \
    --query 'Keys[].KeyId' --output text 2>/dev/null | tr '\t' '\n')

  return 1
}

# Apply/plan: reuse alias key if Enabled; otherwise try binding alias to enabled keys.
bootstrap_resolve_reusable_bootstrap_kms_key() {
  local key_id kms_alias state

  kms_alias="$(bootstrap_kms_alias_name)"

  if bootstrap_kms_alias_exists; then
    key_id="$(aws kms describe-key --key-id "${kms_alias}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' --output text)"
    state="$(bootstrap_kms_key_state "${key_id}")"
    if [ "${state}" = "Enabled" ]; then
      printf '%s\n' "${key_id}"
      return 0
    fi
    echo "Alias ${kms_alias} points to ${key_id} (state=${state}); selecting another Enabled key." >&2
  fi

  while read -r key_id; do
    [ -z "${key_id}" ] && continue
    state="$(bootstrap_kms_key_state "${key_id}")"
    [ "${state}" = "Enabled" ] || continue

    if bootstrap_try_bind_alias_to_key "${key_id}"; then
      printf '%s\n' "${key_id}"
      return 0
    fi
  done < <(aws kms list-keys --region "${AWS_REGION}" \
    --query 'Keys[].KeyId' --output text 2>/dev/null | tr '\t' '\n')

  echo "No reusable KMS key with alias permissions; apply will create aws_kms_key.terraform_state." >&2
  return 1
}

# Destroy/recovery: find bootstrap CMK by alias, bucket SSE, or description (any state).
bootstrap_resolve_dedicated_bootstrap_kms_key() {
  local key_id kms_alias

  kms_alias="$(bootstrap_kms_alias_name)"

  if bootstrap_kms_alias_exists; then
    key_id="$(aws kms describe-key --key-id "${kms_alias}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' --output text)"
    if bootstrap_is_dedicated_bootstrap_kms_key "${key_id}"; then
      printf '%s\n' "${key_id}"
      return 0
    fi
    echo "::warning::Alias ${kms_alias} points to ${key_id}, which is not the bootstrap state CMK; ignoring." >&2
  fi

  if key_id="$(bootstrap_kms_key_id_from_state_bucket 2>/dev/null)"; then
    if bootstrap_is_dedicated_bootstrap_kms_key "${key_id}"; then
      printf '%s\n' "${key_id}"
      return 0
    fi
    echo "::warning::State bucket SSE uses ${key_id}, which is not the bootstrap state CMK; not reusing." >&2
  fi

  bootstrap_discover_dedicated_bootstrap_kms_key
}

# Set TF_BACKEND_KMS_* only when the bootstrap alias points to an Enabled dedicated CMK.
bootstrap_export_reusable_kms_backend_env() {
  local key_id

  unset TF_BACKEND_KMS_KEY_ID TF_STATE_KMS_KEY_ARN
  if ! key_id="$(bootstrap_resolve_reusable_bootstrap_kms_key 2>/dev/null)"; then
    return 1
  fi
  export TF_BACKEND_KMS_KEY_ID="${key_id}"
  export TF_STATE_KMS_KEY_ARN
  TF_STATE_KMS_KEY_ARN="$(aws kms describe-key --key-id "${key_id}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.Arn' --output text)"
  return 0
}

# Wait until KMS key reaches Enabled (or fail after timeout).
bootstrap_wait_kms_key_enabled() {
  local key_id="$1" state attempt=0

  while [ "${attempt}" -lt 30 ]; do
    state="$(aws kms describe-key --key-id "${key_id}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyState' --output text 2>/dev/null || true)"
    if [ "${state}" = "Enabled" ]; then
      echo "Bootstrap KMS key ${key_id} is Enabled."
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  echo "::warning::KMS key ${key_id} not Enabled (state=${state})." >&2
  return 1
}

# Re-enable Disabled keys and cancel PendingDeletion so S3 state read/write works.
bootstrap_restore_kms_key_usability() {
  local key_id="${1:-}" state

  if [ -z "${key_id}" ]; then
    if ! key_id="$(bootstrap_resolve_kms_key_id 2>/dev/null)"; then
      echo "No bootstrap KMS key found to restore."
      return 0
    fi
  fi
  key_id="$(aws kms describe-key --key-id "${key_id}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.KeyId' --output text 2>/dev/null || printf '%s' "${key_id}")"

  state="$(aws kms describe-key --key-id "${key_id}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.KeyState' --output text 2>/dev/null || true)"

  case "${state}" in
    Enabled)
      echo "Bootstrap KMS key ${key_id} is already Enabled."
      return 0
      ;;
    Disabled)
      echo "Enabling disabled KMS key: ${key_id}"
      aws kms enable-key --key-id "${key_id}" --region "${AWS_REGION}"
      bootstrap_wait_kms_key_enabled "${key_id}"
      ;;
    PendingDeletion)
      echo "Cancelling KMS key pending deletion: ${key_id}"
      aws kms cancel-key-deletion --key-id "${key_id}" --region "${AWS_REGION}"
      bootstrap_wait_kms_key_enabled "${key_id}"
      ;;
    *)
      echo "Bootstrap KMS key ${key_id} state: ${state:-unknown} (no action taken)."
      return 0
      ;;
  esac
}

# Backward-compatible name.
bootstrap_cancel_kms_pending_deletion() {
  bootstrap_restore_kms_key_usability "$@"
}

# Ensure bootstrap KMS alias points to selected key.
bootstrap_ensure_kms_alias() {
  local key_id="${1:-}" kms_alias target

  kms_alias="$(bootstrap_kms_alias_name)"
  if [ -z "${key_id}" ]; then
    if ! key_id="$(bootstrap_resolve_reusable_bootstrap_kms_key 2>/dev/null)"; then
      echo "No Enabled KMS key available to attach alias ${kms_alias}; apply will create a new key." >&2
      return 0
    fi
  fi

  if ! bootstrap_try_bind_alias_to_key "${key_id}"; then
    echo "::warning::Unable to bind ${kms_alias} to key ${key_id}; skipping key reuse." >&2
    return 1
  fi

  if bootstrap_kms_alias_exists; then
    target="$(aws kms describe-key --key-id "${kms_alias}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' --output text 2>/dev/null || true)"
    echo "KMS alias ${kms_alias} points to key ${target}."
  fi
  return 0
}

# Recover bootstrap KMS after failed destroy: cancel pending deletion and restore alias.
# Usage: bootstrap_recover_kms [key-id-or-arn]
# Or set BOOTSTRAP_KMS_KEY_ARN / TF_STATE_KMS_KEY_ARN in the environment.
bootstrap_recover_kms() {
  local key_override="${1:-${BOOTSTRAP_KMS_KEY_ARN:-${TF_STATE_KMS_KEY_ARN:-}}}" key_id kms_alias

  tf_common_vars
  kms_alias="$(bootstrap_kms_alias_name)"

  if [ -z "${key_override}" ]; then
    if key_override="$(bootstrap_discover_unusable_bootstrap_kms_key 2>/dev/null)"; then
      echo "Discovered bootstrap KMS key needing recovery: ${key_override}" >&2
    fi
  fi

  if [ -n "${key_override}" ]; then
    key_id="$(aws kms describe-key --key-id "${key_override}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyId' --output text)"
    if ! bootstrap_is_dedicated_bootstrap_kms_key "${key_id}"; then
      echo "::error::${key_override} is not a bootstrap-dedicated CMK (description mismatch)." >&2
      return 1
    fi
    export TF_BACKEND_KMS_KEY_ID="${key_id}"
    export TF_STATE_KMS_KEY_ARN
    TF_STATE_KMS_KEY_ARN="$(aws kms describe-key --key-id "${key_id}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.Arn' --output text)"
  elif ! key_id="$(bootstrap_resolve_dedicated_bootstrap_kms_key 2>/dev/null)"; then
    echo "No bootstrap-dedicated CMK to recover."
    return 0
  else
    key_override="${key_id}"
  fi

  bootstrap_restore_kms_key_usability "${key_override}" || return 1
  bootstrap_ensure_kms_alias || return 1

  key_id="$(bootstrap_resolve_dedicated_bootstrap_kms_key)"
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

# Fail destroy when bootstrap KMS cannot be re-enabled (pending deletion with no discoverable key).
bootstrap_recover_kms_required() {
  if bootstrap_recover_kms; then
    return 0
  fi
  echo "::error::Bootstrap KMS must be Enabled before teardown (enable Disabled, cancel PendingDeletion, or set BOOTSTRAP_KMS_KEY_ARN)." >&2
  return 1
}

# Return 0 when the key must be recovered before bootstrap plan/apply/import.
bootstrap_kms_key_needs_recovery() {
  local key_id="$1" state

  [ -n "${key_id}" ] || return 1
  state="$(aws kms describe-key --key-id "${key_id}" \
    --region "${AWS_REGION}" \
    --query 'KeyMetadata.KeyState' --output text 2>/dev/null || true)"
  [ "${state}" = "PendingDeletion" ] || [ "${state}" = "Disabled" ]
}

# Before bootstrap apply/import: pick an Enabled key, set alias, and use it.
bootstrap_reconcile_orphan_kms() {
  local key_id

  tf_common_vars

  if key_id="$(bootstrap_resolve_reusable_bootstrap_kms_key 2>/dev/null)"; then
    echo "Using bootstrap CMK ${key_id} (alias $(bootstrap_kms_alias_name), Enabled)."
    export TF_BACKEND_KMS_KEY_ID="${key_id}"
    export TF_STATE_KMS_KEY_ARN
    TF_STATE_KMS_KEY_ARN="$(aws kms describe-key --key-id "${key_id}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.Arn' --output text)"
    return 0
  fi

  echo "No reusable bootstrap CMK; terraform apply will create aws_kms_key.terraform_state and a new alias."
  unset TF_BACKEND_KMS_KEY_ID TF_STATE_KMS_KEY_ARN
  return 0
}

# Run before bootstrap plan/apply in CI or locally (never fails; does not cancel deletion or enable keys).
bootstrap_prepare_apply() {
  bootstrap_reconcile_orphan_kms

  if bootstrap_state_bucket_exists; then
    export TF_BACKEND_BUCKET="$(bootstrap_state_bucket_name)"
    export TF_BACKEND_REGION="${AWS_REGION}"
    export TF_BACKEND_DYNAMODB_TABLE="$(bootstrap_dynamodb_table_name)"
    export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"
  fi
}

# Pull remote state, empty the versioned bucket, and use local state for the final destroy (no S3 writes).
bootstrap_switch_to_local_state_for_teardown() {
  local bootstrap_dir="${1:-global/bootstrap}"
  local bootstrap_abs bucket

  bootstrap_abs="$(bootstrap_dir_abs "${bootstrap_dir}")"
  bucket="$(bootstrap_state_bucket_name)"
  bootstrap_recover_kms_required || return 1

  pushd "${bootstrap_abs}" >/dev/null
  echo "Pulling bootstrap state from S3 before bucket teardown..."
  if ! terraform state pull >terraform.tfstate.teardown 2>/dev/null; then
    if [ -f terraform.tfstate ]; then
      cp terraform.tfstate terraform.tfstate.teardown
    else
      echo "::warning::Could not pull remote state; final destroy uses current workspace state." >&2
      : >terraform.tfstate.teardown
    fi
  fi

  popd >/dev/null

  if bootstrap_state_bucket_exists; then
    echo "Emptying state bucket ${bucket} (all object versions and lockfiles)..."
    bootstrap_empty_state_bucket_all_versions "${bucket}"
    clear_s3_state_lockfiles "${bucket}"
  fi

  pushd "${bootstrap_abs}" >/dev/null
  echo "Switching to local backend for final bootstrap destroy (prevents state writes to S3/KMS)..."
  bootstrap_activate_local_backend_file "${bootstrap_abs}"
  rm -rf .terraform
  terraform init -input=false -reconfigure
  if [ -s terraform.tfstate.teardown ]; then
    mv terraform.tfstate.teardown terraform.tfstate
  fi
  popd >/dev/null
}

# Tear down bootstrap KMS: cancel pending deletion, empty state bucket, delete alias, schedule key deletion.
# Usage: bootstrap_remove_pending_kms [key-id-or-arn]
bootstrap_remove_pending_kms() {
  local key_override="${1:-${BOOTSTRAP_KMS_KEY_ARN:-${TF_STATE_KMS_KEY_ARN:-}}}" key_id kms_alias bucket

  tf_common_vars
  kms_alias="$(bootstrap_kms_alias_name)"
  bucket="$(bootstrap_state_bucket_name)"

  if [ -z "${key_override}" ]; then
    key_override="$(bootstrap_discover_pending_bootstrap_kms_key 2>/dev/null || true)"
  fi
  if [ -z "${key_override}" ]; then
    echo "::error::Pass key ARN/ID: bootstrap_remove_pending_kms arn:aws:kms:...:key/..." >&2
    return 1
  fi

  echo "Step 1/4: Re-enable KMS key (required to delete encrypted S3 state objects)..."
  bootstrap_recover_kms "${key_override}" || return 1

  key_id="$(bootstrap_resolve_kms_key_id)"

  if bootstrap_state_bucket_exists; then
    echo "Step 2/4: Empty state bucket ${bucket} (all versions)..."
    bootstrap_empty_state_bucket_all_versions "${bucket}"
    clear_s3_state_lockfiles "${bucket}"
  fi

  echo "Step 3/4: Delete alias ${kms_alias} (if present)..."
  if bootstrap_kms_alias_exists; then
    aws kms delete-alias --alias-name "${kms_alias}" --region "${AWS_REGION}"
  fi

  echo "Step 4/4: Schedule KMS key ${key_id} for deletion (7 day window)..."
  aws kms schedule-key-deletion \
    --key-id "${key_id}" \
    --pending-window-in-days 7 \
    --region "${AWS_REGION}"
  echo "KMS key ${key_id} is PendingDeletion. Bucket should be gone; key deletes after waiting period."
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

  if bootstrap_export_reusable_kms_backend_env; then
    return 0
  fi

  echo "State bucket exists but bootstrap alias/KMS is not reusable; S3 backend init omits kms_key_id." >&2
  unset TF_BACKEND_KMS_KEY_ID TF_STATE_KMS_KEY_ARN
}

# Resolve TF_BACKEND_* for plan/destroy when bootstrap was applied in a previous run.
resolve_bootstrap_backend_env() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"

  if [ -n "${TF_STATE_BUCKET:-}" ] \
    && [ -n "${TF_STATE_DYNAMODB_TABLE:-}" ]; then
    if ! bootstrap_state_migrated_to_s3; then
      echo "::warning::TF_STATE_* variables are set but bootstrap state is missing or placeholder in S3; using recovery init." >&2
    else
      export TF_BACKEND_BUCKET="${TF_STATE_BUCKET}"
      export TF_BACKEND_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE}"
      export TF_BACKEND_REGION="${AWS_REGION}"
      if [ -n "${TF_STATE_KMS_KEY_ID:-}" ] \
        && [ "$(bootstrap_kms_key_state "${TF_STATE_KMS_KEY_ID}")" = "Enabled" ] \
        && bootstrap_is_dedicated_bootstrap_kms_key "${TF_STATE_KMS_KEY_ID}"; then
        export TF_BACKEND_KMS_KEY_ID="${TF_STATE_KMS_KEY_ID}"
        export TF_STATE_KMS_KEY_ARN="${TF_STATE_KMS_KEY_ARN:-}"
      else
        unset TF_BACKEND_KMS_KEY_ID TF_STATE_KMS_KEY_ARN
        echo "::warning::Repository KMS variables point to a non-reusable key; omitting kms_key_id from backend init." >&2
      fi
      echo "Using bootstrap backend from repository variables."
      return 0
    fi
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
  bootstrap_terraform_init_s3
  popd >/dev/null
}

maybe_migrate_bootstrap_state() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"

  if bootstrap_state_migrated_to_s3; then
    bootstrap_restore_s3_backend_file "${bootstrap_dir}"
    bootstrap_enable_state_locking "${bootstrap_dir}"
    return 0
  fi

  bootstrap_clear_stale_s3_bootstrap_state || true

  if [ -f "${bootstrap_dir}/terraform.tfstate" ]; then
    export_bootstrap_outputs "${bootstrap_dir}"
    bootstrap_restore_s3_backend_file "${bootstrap_dir}"
    pushd "${bootstrap_dir}" >/dev/null
    export TF_BACKEND_KEY="$(bootstrap_state_s3_key)"
    bootstrap_terraform_init_s3 migrate
    popd >/dev/null
    bootstrap_enable_state_locking "${bootstrap_dir}"
    return 0
  fi

  echo "::warning::No local terraform.tfstate; recovering bootstrap state via S3 import." >&2
  bootstrap_restore_s3_backend_file "${bootstrap_dir}"
  bootstrap_set_backend_for_existing_bucket
  pushd "${bootstrap_dir}" >/dev/null
  export TF_BACKEND_KEY="$(bootstrap_state_s3_key)"
  bootstrap_terraform_init_s3
  popd >/dev/null
  import_existing_bootstrap_resources "${bootstrap_dir}"
  bootstrap_enable_state_locking "${bootstrap_dir}"
}

# Re-init bootstrap backend with S3 lockfile-based state locking.
bootstrap_apply_backend_env_from_repo_vars() {
  if [ -z "${TF_STATE_BUCKET:-}" ]; then
    return 1
  fi
  if ! aws s3api head-bucket --bucket "${TF_STATE_BUCKET}" --region "${AWS_REGION}" 2>/dev/null; then
    echo "::warning::TF_STATE_BUCKET=${TF_STATE_BUCKET} is not reachable; falling back to local bootstrap init." >&2
    return 1
  fi
  if ! bootstrap_state_migrated_to_s3; then
    echo "::warning::TF_STATE_BUCKET is set but bootstrap state is not in S3 yet; falling back to recovery init." >&2
    return 1
  fi

  export TF_BACKEND_BUCKET="${TF_STATE_BUCKET}"
  export TF_BACKEND_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE}"
  export TF_BACKEND_REGION="${AWS_REGION}"
  unset TF_BACKEND_KMS_KEY_ID TF_STATE_KMS_KEY_ARN
  if [ -n "${TF_STATE_KMS_KEY_ID:-}" ] \
    && [ "$(bootstrap_kms_key_state "${TF_STATE_KMS_KEY_ID}")" = "Enabled" ] \
    && bootstrap_is_dedicated_bootstrap_kms_key "${TF_STATE_KMS_KEY_ID}"; then
    export TF_BACKEND_KMS_KEY_ID="${TF_STATE_KMS_KEY_ID}"
    export TF_STATE_KMS_KEY_ARN="${TF_STATE_KMS_KEY_ARN:-}"
  elif bootstrap_state_bucket_exists; then
    bootstrap_set_backend_for_existing_bucket
  fi
  return 0
}

bootstrap_enable_state_locking() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  tf_common_vars

  pushd "${bootstrap_dir}" >/dev/null
  if [ -n "${TF_STATE_BUCKET:-}" ]; then
    bootstrap_apply_backend_env_from_repo_vars
  elif bootstrap_state_bucket_exists; then
    bootstrap_set_backend_for_existing_bucket
  else
    popd >/dev/null
    return 0
  fi
  export TF_BACKEND_KEY="global/bootstrap/terraform.tfstate"
  echo "Enabling S3 lockfile state locking..."
  bootstrap_terraform_init_s3
  popd >/dev/null
}

bootstrap_resolve_s3_backend_env() {
  if [ -n "${TF_STATE_BUCKET:-}" ] && bootstrap_apply_backend_env_from_repo_vars; then
    :
  elif bootstrap_state_bucket_exists; then
    bootstrap_set_backend_for_existing_bucket
  else
    return 1
  fi
  export TF_BACKEND_KEY="${TF_BACKEND_KEY:-global/bootstrap/terraform.tfstate}"
  return 0
}

bootstrap_init() {
  local bootstrap_dir mode
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  mode="$(bootstrap_init_mode)"

  case "${mode}" in
    local)
      bootstrap_init_local "${bootstrap_dir}"
      ;;
    partial_s3)
      bootstrap_init_partial_s3 "${bootstrap_dir}"
      ;;
    remote)
      echo "Bootstrap init: remote S3 backend (state already in bucket)."
      bootstrap_restore_s3_backend_file "${bootstrap_dir}"
      pushd "${bootstrap_dir}" >/dev/null
      bootstrap_resolve_s3_backend_env
      bootstrap_terraform_init_s3
      popd >/dev/null
      ;;
    *)
      echo "::error::Unknown bootstrap init mode: ${mode}" >&2
      return 1
      ;;
  esac
}

# Plan/apply in the bootstrap module after backend init (same directory, TF 1.7+).
bootstrap_run_plan() {
  local bootstrap_dir="${1:-global/bootstrap}"
  bootstrap_prepare_apply
  bootstrap_init "${bootstrap_dir}" || return 1
  pushd "$(bootstrap_dir_abs "${bootstrap_dir}")" >/dev/null
  mapfile -t var_args < <(tf_var_args)
  terraform plan -input=false -no-color "${var_args[@]}"
  popd >/dev/null
}

bootstrap_run_apply() {
  local bootstrap_dir="${1:-global/bootstrap}"
  bootstrap_prepare_apply
  bootstrap_init "${bootstrap_dir}" || return 1
  pushd "$(bootstrap_dir_abs "${bootstrap_dir}")" >/dev/null
  mapfile -t var_args < <(tf_var_args)
  mapfile -t destroy_args < <(bootstrap_destroy_var_args)
  terraform apply -input=false -auto-approve -no-color "${var_args[@]}" "${destroy_args[@]}"
  popd >/dev/null
}

# Import bootstrap resources that already exist in AWS but are missing from state
# (for example after a partial apply or lost local state before S3 migration).
import_existing_bootstrap_resources() {
  local bootstrap_dir
  bootstrap_dir="$(bootstrap_dir_abs "${1:-global/bootstrap}")"
  tf_common_vars
  bootstrap_prepare_apply

  local name_prefix="${TF_PROJECT_NAME}-${TF_ENVIRONMENT}"
  local state_bucket="${name_prefix}-terraform-state-${AWS_ACCOUNT_ID}"
  local dynamodb_table="${name_prefix}-terraform-locks"
  local kms_alias="alias/${TF_PROJECT_NAME}-${TF_ENVIRONMENT}-terraform-state"

  pushd "${bootstrap_dir}" >/dev/null
  local init_mode
  init_mode="$(bootstrap_init_mode)"
  case "${init_mode}" in
    local)
      bootstrap_init_local "${bootstrap_dir}"
      ;;
    partial_s3)
      bootstrap_init_partial_s3 "${bootstrap_dir}"
      ;;
    remote)
      bootstrap_init "${bootstrap_dir}"
      ;;
    *)
      echo "::error::Unknown bootstrap init mode: ${init_mode}" >&2
      popd >/dev/null
      return 1
      ;;
  esac
  mapfile -t var_args < <(tf_var_args)
  mapfile -t state_args < <(bootstrap_local_state_args)

  terraform_state_has() {
    local addr="$1"
    terraform state show -no-color "${state_args[@]}" "${addr}" &>/dev/null
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

  local key_id=""
  if key_id="$(bootstrap_resolve_reusable_bootstrap_kms_key 2>/dev/null)"; then
    echo "Importing reusable bootstrap CMK ${key_id} into Terraform state..." >&2
    import_if_missing aws_kms_key.terraform_state "${key_id}"
    import_if_missing aws_kms_alias.terraform_state "${kms_alias}"
  else
    echo "No reusable bootstrap CMK to import; apply will create aws_kms_key.terraform_state." >&2
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
  cluster_addr="$(dev_eks_cluster_state_addr)"

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
  mapfile -t var_args < <(tf_var_args)
  mapfile -t dev_args < <(tf_dev_extra_var_args)
  set +e
  import_out="$(terraform import -input=false "${var_args[@]}" "${dev_args[@]}" "${cluster_addr}" "${cluster_name}" 2>&1)"
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
  cluster_addr="$(dev_eks_cluster_state_addr)"

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

# API mode is irreversible. CONFIG_MAP can upgrade in-place to API_AND_CONFIG_MAP.
recover_dev_cluster_if_api_mode() {
  local dev_abs="${1:-environments/dev}"
  local cluster_name auth_mode node_role_arn repo_root did_pushd=false
  local ng addr

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"
  repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    return 0
  fi

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"

  case "${auth_mode}" in
    API_AND_CONFIG_MAP)
      return 0
      ;;
    CONFIG_MAP)
      echo "Cluster ${cluster_name} is CONFIG_MAP; upgrading to API_AND_CONFIG_MAP in-place..."
      upgrade_eks_authentication_mode_if_needed
      return 0
      ;;
  esac

  echo "::warning::Cluster ${cluster_name} auth mode is ${auth_mode} (irreversible)."
  echo "Managed node groups require API_AND_CONFIG_MAP. Deleting cluster for recreation..."

  node_role_arn="$(node_iam_role_arn "${cluster_name}")"

  for ng in $(aws eks list-nodegroups \
    --cluster-name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroups[]' \
    --output text 2>/dev/null); do
    [ -z "${ng}" ] || [ "${ng}" = "None" ] && continue
    echo "Deleting node group ${ng}..."
    aws eks delete-nodegroup \
      --cluster-name "${cluster_name}" \
      --nodegroup-name "${ng}" \
      --region "${AWS_REGION}" || true
    aws eks wait nodegroup-deleted \
      --cluster-name "${cluster_name}" \
      --nodegroup-name "${ng}" \
      --region "${AWS_REGION}" || true
  done

  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${AWS_REGION}" \
    bash "${repo_root}/modules/eks/scripts/delete-node-access-entry.sh" || true

  echo "Deleting EKS cluster ${cluster_name}..."
  aws eks delete-cluster --name "${cluster_name}" --region "${AWS_REGION}"
  aws eks wait cluster-deleted --name "${cluster_name}" --region "${AWS_REGION}"

  local log_group_name="/aws/eks/${cluster_name}/cluster"
  if aws logs describe-log-groups --log-group-name-prefix "${log_group_name}" \
    --query "logGroups[?logGroupName=='${log_group_name}'] | length(@)" --output text 2>/dev/null | grep -q '^1$'; then
    echo "Deleting orphaned CloudWatch log group ${log_group_name}..."
    aws logs delete-log-group --log-group-name "${log_group_name}" --region "${AWS_REGION}" || true
  fi

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  while IFS= read -r addr; do
    [ -z "${addr}" ] && continue
    echo "Removing ${addr} from Terraform state..."
    terraform state rm -no-color "${addr}" || true
  done < <(terraform state list -no-color 2>/dev/null | grep -E '^module\.eks\[0\]\.' || true)

  [ "${did_pushd}" = true ] && popd >/dev/null

  echo "EKS cluster removed. This apply will recreate it with API_AND_CONFIG_MAP."
}

# Deprecated: do not migrate to API mode (breaks managed node groups).
migrate_dev_cluster_to_api_node_auth() {
  recover_dev_cluster_if_api_mode "${1:-environments/dev}"
}

# Remove Terraform state for EKS-managed access entry (no longer in configuration).
import_eks_node_access_to_state() {
  local dev_abs="${1:-environments/dev}"
  local did_pushd=false

  dev_abs="$(resolve_dev_dir "${dev_abs}")"

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  terraform state rm "$(dev_eks_state_prefix).aws_eks_access_entry.node[0]" 2>/dev/null || true
  terraform state rm "$(dev_eks_state_prefix).aws_eks_access_policy_association.node[0]" 2>/dev/null || true
  echo "Node access entry is not Terraform-managed; managed nodes use EKS access entry + aws-auth in API_AND_CONFIG_MAP."

  [ "${did_pushd}" = true ] && popd >/dev/null
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
      terraform state rm "$(dev_eks_state_prefix).aws_eks_node_group.main[\"general\"]" 2>/dev/null || true
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
      local node_role_arn repo_root
      node_role_arn="$(node_iam_role_arn "${cluster_name}")"
      repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
      echo "Resetting node access entry before recreating failed node group ${nodegroup_name}..."
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${AWS_REGION}" \
        bash "${repo_root}/modules/eks/scripts/delete-node-access-entry.sh" || true
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
        terraform state rm "$(dev_eks_state_prefix).aws_eks_node_group.main[\"general\"]" 2>/dev/null || true
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

# Drop stale state addresses from older module versions.
cleanup_stale_eks_auth_state() {
  local dev_abs="${1:-environments/dev}"
  local did_pushd=false
  local cluster_name auth_mode

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  cluster_name="$(eks_cluster_name)"

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  terraform state rm "$(dev_eks_state_prefix).aws_launch_template.node_group[\"general\"]" 2>/dev/null || true
  terraform state rm "$(dev_eks_state_prefix).kubernetes_config_map_v1.aws_auth[0]" 2>/dev/null || true
  terraform state rm "$(dev_eks_state_prefix).aws_eks_access_policy_association.node[0]" 2>/dev/null || true
  terraform state rm "$(dev_eks_state_prefix).null_resource.aws_auth_node_role[0]" 2>/dev/null || true
  # Managed node groups: access entry is EKS-managed, not Terraform-managed.
  terraform state rm "$(dev_eks_state_prefix).aws_eks_access_entry.node[0]" 2>/dev/null || true

  if eks_cluster_exists_in_aws "${cluster_name}"; then
    auth_mode="$(aws eks describe-cluster \
      --name "${cluster_name}" \
      --region "${AWS_REGION}" \
      --query 'cluster.accessConfig.authenticationMode' \
      --output text 2>/dev/null || echo "unknown")"
    echo "Auth mode ${auth_mode}: managed nodes need EKS access entry + aws-auth in API_AND_CONFIG_MAP."
  fi

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
    -target="$(dev_eks_cluster_state_addr)"

  [ "${did_pushd}" = true ] && popd >/dev/null
}

node_iam_role_arn() {
  local cluster_name="${1:-$(eks_cluster_name)}"
  aws iam get-role \
    --role-name "${cluster_name}-node" \
    --query 'Role.Arn' \
    --output text
}

cluster_iam_role_arn() {
  local cluster_name="${1:-$(eks_cluster_name)}"
  aws iam get-role \
    --role-name "${cluster_name}-cluster" \
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
    API_AND_CONFIG_MAP)
      echo "--- aws-auth mapRoles after ensure ---"
      kubectl get configmap aws-auth -n kube-system -o jsonpath='{.data.mapRoles}' 2>/dev/null || true
      echo ""
      if ! kubectl get configmap aws-auth -n kube-system -o yaml | grep -Fq "${node_role_arn}"; then
        echo "::error::Node role ${node_role_arn} not found in aws-auth mapRoles."
        return 1
      fi
      echo "aws-auth mapRoles contains node role."
      if ! aws eks describe-access-entry \
        --cluster-name "${cluster_name}" \
        --principal-arn "${node_role_arn}" \
        --region "${AWS_REGION}" &>/dev/null; then
        echo "::warning::Node access entry not present yet (EKS creates it with the managed node group)."
      else
        echo "Node EC2_LINUX access entry present (API_AND_CONFIG_MAP requires entry + aws-auth)."
      fi
      ;;
    CONFIG_MAP | *)
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
  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars
  ensure_node_cluster_auth_for_dev
}

# Repair stuck node join: remove CLI access entries, refresh aws-auth, recycle instances.
repair_dev_node_join_if_needed() {
  local dev_abs="${1:-environments/dev}"
  local cluster_name nodegroup_name node_role_arn repo_root
  local auth_mode ready desired

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars

  if ! dev_stack_enable_eks_nodes; then
    return 0
  fi

  cluster_name="$(eks_cluster_name)"
  nodegroup_name="general"
  repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

  if ! eks_cluster_exists_in_aws "${cluster_name}"; then
    return 0
  fi

  if ! aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" &>/dev/null; then
    return 0
  fi

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text 2>/dev/null || echo "unknown")"

  if [ "${auth_mode}" != "API_AND_CONFIG_MAP" ]; then
    return 0
  fi

  status="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.status' \
    --output text 2>/dev/null || echo "unknown")"

  if [ "${status}" = "CREATE_FAILED" ] || [ "${status}" = "DELETING" ]; then
    return 0
  fi

  node_role_arn="$(node_iam_role_arn "${cluster_name}")"
  desired="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.scalingConfig.desiredSize' \
    --output text 2>/dev/null || echo "0")"

  if [ "${desired}" -le 0 ] 2>/dev/null; then
    return 0
  fi

  aws eks update-kubeconfig --name "${cluster_name}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
  ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready" { n++ } END { print n + 0 }')"

  if [ "${ready}" -ge "${desired}" ] && [ "${ready}" -gt 0 ]; then
    echo "Node join OK: Ready=${ready}/${desired}."
    return 0
  fi

  echo "Node join repair: Ready=${ready}/${desired} on ${cluster_name}/${nodegroup_name}."

  python3 -c "import yaml" 2>/dev/null || pip install --user pyyaml

  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${AWS_REGION}" \
    bash "${repo_root}/modules/eks/scripts/ensure-node-cluster-auth.sh"

  ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready" { n++ } END { print n + 0 }')"
  if [ "${ready}" -ge "${desired}" ] && [ "${ready}" -gt 0 ]; then
    echo "Node join repair succeeded: Ready=${ready}/${desired}."
    return 0
  fi

  echo "Recycling node group instances so kubelets pick up aws-auth..."
  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${AWS_REGION}" \
    NODEGROUP_NAME="${nodegroup_name}" \
    bash "${repo_root}/modules/eks/scripts/recycle-nodegroup-instances.sh"

  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${AWS_REGION}" \
    NODEGROUP_NAME="${nodegroup_name}" DESIRED_SIZE="${desired}" \
    bash "${repo_root}/modules/eks/scripts/wait-for-ready-nodes.sh" || {
      echo "::warning::Node join repair did not reach Ready=${desired} before apply; continuing."
      return 0
    }
}

# Required AWS-managed policies on the EKS node IAM role.
diag_node_required_iam_policies() {
  printf '%s\n' \
    "AmazonEKSWorkerNodePolicy" \
    "AmazonEKS_CNI_Policy" \
    "AmazonEC2ContainerRegistryReadOnly"
}

# CHECK 1 — aws-auth mapRoles contains the node role with correct groups.
diag_node_join_check_aws_auth() {
  local cluster_name="$1"
  local node_role_arn="$2"
  local auth_mode="$3"
  local map_roles aws_auth_ok=false

  echo ""
  echo "========== CHECK 1: aws-auth gatekeeper (mapRoles) =========="
  echo "Expected node role ARN: ${node_role_arn}"
  echo "If this ARN is missing or mistyped in mapRoles, kubelet gets Unauthorized."

  if [ "${auth_mode}" = "API" ]; then
    echo "SKIP: cluster auth mode is API (uses access entries, not aws-auth)."
    return 0
  fi

  aws eks update-kubeconfig --name "${cluster_name}" --region "${AWS_REGION}" >/dev/null 2>&1 || true

  if ! kubectl get configmap aws-auth -n kube-system &>/dev/null; then
    echo "RESULT: FAIL — ConfigMap aws-auth not found in kube-system."
    echo "  Managed node groups normally create it when the node group is created."
    return 1
  fi

  map_roles="$(kubectl get configmap aws-auth -n kube-system -o jsonpath='{.data.mapRoles}' 2>/dev/null || true)"
  echo "--- mapRoles ---"
  if [ -n "${map_roles}" ]; then
    printf '%s\n' "${map_roles}"
  else
    echo "(empty or unreadable)"
  fi

  if printf '%s\n' "${map_roles}" | grep -Fq "${node_role_arn}"; then
    echo "RESULT: PASS — exact node role ARN found in mapRoles."
    aws_auth_ok=true
  else
    echo "RESULT: FAIL — node role ARN not found in mapRoles (typo or missing entry)."
  fi

  if printf '%s\n' "${map_roles}" | grep -Fq "system:bootstrappers"; then
    echo "RESULT: PASS — system:bootstrappers group present in mapRoles."
  else
    echo "RESULT: FAIL — system:bootstrappers missing from mapRoles."
    aws_auth_ok=false
  fi

  if printf '%s\n' "${map_roles}" | grep -Fq "system:nodes"; then
    echo "RESULT: PASS — system:nodes group present in mapRoles."
  else
    echo "RESULT: FAIL — system:nodes missing from mapRoles."
    aws_auth_ok=false
  fi

  if printf '%s\n' "${map_roles}" | grep -Fq 'system:node:{{EC2PrivateDNSName}}'; then
    echo "RESULT: PASS — username template system:node:{{EC2PrivateDNSName}} present."
  else
    echo "RESULT: WARN — expected username template system:node:{{EC2PrivateDNSName}} not seen."
  fi

  [ "${aws_auth_ok}" = true ]
}

# CHECK 2 — who is responsible for writing aws-auth in this repo.
diag_node_join_check_aws_auth_ownership() {
  local cluster_name="$1"
  local nodegroup_name="$2"
  local ng_status map_roles

  echo ""
  echo "========== CHECK 2: Who updates aws-auth? =========="
  echo "In this repo:"
  echo "  • EKS (primary): aws_eks_node_group creates/updates kube-system/aws-auth on node group create."
  echo "  • Terraform: does NOT pre-merge aws-auth (modules/eks/aws_auth.tf — comment only)."
  echo "  • CI fallback: prepare-managed-node-aws-auth.sh on repair if role missing from mapRoles."
  echo "  • CI reset: delete-node-access-entry.sh + delete failed NG before recreate."

  ng_status="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.status' \
    --output text 2>/dev/null || echo "NOT_FOUND")"

  echo "Node group ${nodegroup_name} status: ${ng_status}"

  aws eks update-kubeconfig --name "${cluster_name}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
  if kubectl get configmap aws-auth -n kube-system &>/dev/null; then
    map_roles="$(kubectl get configmap aws-auth -n kube-system -o jsonpath='{.data.mapRoles}' 2>/dev/null || true)"
    if [ -n "${map_roles}" ]; then
      echo "RESULT: PASS — aws-auth ConfigMap exists (EKS or CI wrote it)."
    else
      echo "RESULT: WARN — aws-auth exists but mapRoles is empty; nobody has mapped node roles yet."
    fi
  elif [ "${ng_status}" = "NOT_FOUND" ] || [ "${ng_status}" = "DELETING" ]; then
    echo "RESULT: INFO — no aws-auth yet (node group not created or was deleted)."
  else
    echo "RESULT: FAIL — node group exists but aws-auth ConfigMap is missing."
  fi
}

# CHECK 3 — node IAM role has worker/CNI/ECR policies attached.
diag_node_join_check_iam_policies() {
  local node_role_arn="$1"
  local role_name policy missing=0

  role_name="${node_role_arn##*/}"

  echo ""
  echo "========== CHECK 3: Node IAM role policies =========="
  echo "Role: ${node_role_arn}"
  echo "Required AWS-managed policies for bootstrap + CNI + image pull:"

  if ! aws iam get-role --role-name "${role_name}" &>/dev/null; then
    echo "RESULT: FAIL — IAM role ${role_name} does not exist."
    return 1
  fi

  echo "--- attached policies ---"
  local attached
  attached="$(aws iam list-attached-role-policies \
    --role-name "${role_name}" \
    --output text 2>/dev/null || true)"
  if [ -n "${attached}" ]; then
    printf '%s\n' "${attached}"
  else
    echo "(none or could not list)"
  fi

  while IFS= read -r policy; do
    [ -z "${policy}" ] && continue
    if printf '%s\n' "${attached}" | grep -q "${policy}"; then
      echo "RESULT: PASS — ${policy} attached."
    else
      echo "RESULT: FAIL — ${policy} NOT attached (node cannot bootstrap/pull images/CNI)."
      missing=$((missing + 1))
    fi
  done < <(diag_node_required_iam_policies)

  echo "--- inline policies (informational) ---"
  aws iam list-role-policies --role-name "${role_name}" --output text 2>/dev/null \
    || echo "(none or could not list)"

  [ "${missing}" -eq 0 ]
}

# CHECK 4 — nodes can reach the Kubernetes API (endpoint, routes, SGs, VPC endpoints).
diag_node_join_check_network() {
  local cluster_name="$1"
  local nodegroup_name="$2"
  local vpc_id cluster_sg private_access public_access
  local subnet_ids subnet_id rt nat_ok=false endpoints_ok=true

  echo ""
  echo "========== CHECK 4: Node → control plane network =========="
  echo "Unauthorized usually means auth failed, but unreachable API can look similar in logs."
  echo "Verify endpoint access, private subnet routing, and cluster security group rules."

  vpc_id="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.resourcesVpcConfig.vpcId' \
    --output text 2>/dev/null || echo "")"
  cluster_sg="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
    --output text 2>/dev/null || echo "")"
  private_access="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.resourcesVpcConfig.endpointPrivateAccess' \
    --output text 2>/dev/null || echo "unknown")"
  public_access="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.resourcesVpcConfig.endpointPublicAccess' \
    --output text 2>/dev/null || echo "unknown")"

  echo "--- cluster API endpoint ---"
  aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.{endpoint:endpoint,privateAccess:resourcesVpcConfig.endpointPrivateAccess,publicAccess:resourcesVpcConfig.endpointPublicAccess,vpcId:resourcesVpcConfig.vpcId,clusterSecurityGroupId:resourcesVpcConfig.clusterSecurityGroupId,extraSecurityGroups:resourcesVpcConfig.securityGroupIds}' \
    --output json 2>/dev/null || true

  if [ "${private_access}" = "True" ] || [ "${private_access}" = "true" ]; then
    echo "RESULT: PASS — private API endpoint enabled (nodes in VPC should use it)."
  else
    echo "RESULT: WARN — private API endpoint disabled; nodes rely on public endpoint + NAT."
  fi

  subnet_ids="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.subnets' \
    --output text 2>/dev/null || echo "")"

  echo "--- node group subnets ---"
  if [ -n "${subnet_ids}" ] && [ "${subnet_ids}" != "None" ]; then
    printf '  %s\n' ${subnet_ids}
  else
    echo "  (node group not found or no subnets)"
  fi

  echo "--- private subnet routes (need NAT or egress for public API / image pull) ---"
  for subnet_id in ${subnet_ids}; do
    [ -z "${subnet_id}" ] || [ "${subnet_id}" = "None" ] && continue
    echo "Subnet ${subnet_id}:"
    aws ec2 describe-route-tables \
      --filters "Name=association.subnet-id,Values=${subnet_id}" \
      --region "${AWS_REGION}" \
      --query 'RouteTables[0].Routes' \
      --output table 2>/dev/null || echo "  (could not read route table)"
    if aws ec2 describe-route-tables \
      --filters "Name=association.subnet-id,Values=${subnet_id}" \
      --region "${AWS_REGION}" \
      --query 'RouteTables[0].Routes[?NatGatewayId!=null || GatewayId!=null]' \
      --output text 2>/dev/null | grep -q .; then
      echo "  RESULT: PASS — default route via NAT gateway or IGW present."
      nat_ok=true
    else
      echo "  RESULT: WARN — no NAT/IGW default route; outbound internet may fail."
    fi
  done

  if [ -n "${vpc_id}" ] && [ "${vpc_id}" != "None" ]; then
    echo "--- VPC interface endpoints (recommended for private nodes) ---"
    aws ec2 describe-vpc-endpoints \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --region "${AWS_REGION}" \
      --query 'VpcEndpoints[].{Service:ServiceName,State:State}' \
      --output table 2>/dev/null || true
    for svc in "com.amazonaws.${AWS_REGION}.eks" "com.amazonaws.${AWS_REGION}.sts" "com.amazonaws.${AWS_REGION}.ec2"; do
      if aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=${vpc_id}" "Name=service-name,Values=${svc}" \
        --region "${AWS_REGION}" \
        --query 'VpcEndpoints[?State==`available`] | length(@)' \
        --output text 2>/dev/null | grep -q '^[1-9]'; then
        echo "RESULT: PASS — VPC endpoint ${svc} available."
      else
        echo "RESULT: WARN — VPC endpoint ${svc} not available (may use NAT instead)."
        endpoints_ok=false
      fi
    done
  fi

  if [ -n "${cluster_sg}" ] && [ "${cluster_sg}" != "None" ]; then
    echo "--- cluster security group (managed nodes use this SG) ---"
    echo "ClusterSecurityGroupId=${cluster_sg}"
    aws ec2 describe-security-groups \
      --group-ids "${cluster_sg}" \
      --region "${AWS_REGION}" \
      --query 'SecurityGroups[0].IpPermissions[?FromPort==`443` || IpProtocol==`-1`]' \
      --output json 2>/dev/null || echo "(could not read SG rules)"
    if aws ec2 describe-security-groups \
      --group-ids "${cluster_sg}" \
      --region "${AWS_REGION}" \
      --query 'SecurityGroups[0].IpPermissions[?UserIdGroupPairs[?GroupId==`'${cluster_sg}'`]]]' \
      --output text 2>/dev/null | grep -q .; then
      echo "RESULT: PASS — cluster SG allows traffic from itself (control plane ↔ nodes)."
    else
      echo "RESULT: INFO — verify cluster SG allows node ↔ API on 443 (EKS usually adds this)."
    fi
  fi

  # Quick API reachability from CI (not from node, but confirms endpoint is up).
  echo "--- API reachability from CI runner (not from node) ---"
  if aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.status' \
    --output text 2>/dev/null | grep -q ACTIVE; then
    echo "RESULT: PASS — cluster status ACTIVE (API endpoint registered)."
  else
    echo "RESULT: FAIL — cluster not ACTIVE."
  fi

  { [ "${nat_ok}" = true ] || [ "${public_access}" = "True" ] || [ "${public_access}" = "true" ]; } \
    && [ "${endpoints_ok}" = true ] || [ "${nat_ok}" = true ]
}

# CHECK 5 — cluster IAM role can ec2:DescribeInstances for aws-auth {{EC2PrivateDNSName}}.
diag_node_join_check_cluster_role_ec2() {
  local cluster_name="$1"
  local cluster_role_arn role_name attached decision

  cluster_role_arn="$(cluster_iam_role_arn "${cluster_name}" 2>/dev/null \
    || echo "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${cluster_name}-cluster")"
  role_name="${cluster_role_arn##*/}"

  echo ""
  echo "========== CHECK 5: Cluster role EC2 (authenticator {{EC2PrivateDNSName}}) =========="
  echo "When a node authenticates, the EKS control plane resolves username"
  echo "system:node:{{EC2PrivateDNSName}} by calling ec2:DescribeInstances as the"
  echo "CLUSTER role (${cluster_role_arn}), not the node role."
  echo "Without ec2:DescribeInstances on the cluster role, authenticator logs show:"
  echo "  failed querying private DNS from EC2 API ... not authorized: ec2:DescribeInstances"

  if ! aws iam get-role --role-name "${role_name}" &>/dev/null; then
    echo "RESULT: FAIL — IAM role ${role_name} does not exist."
    return 1
  fi

  echo "--- attached policies (cluster role) ---"
  attached="$(aws iam list-attached-role-policies \
    --role-name "${role_name}" \
    --output text 2>/dev/null || true)"
  if [ -n "${attached}" ]; then
    printf '%s\n' "${attached}"
  else
    echo "(none or could not list)"
  fi

  decision="$(aws iam simulate-principal-policy \
    --policy-source-arn "${cluster_role_arn}" \
    --action-names ec2:DescribeInstances \
    --resource-arns "*" \
    --query 'EvaluationResults[0].EvalDecision' \
    --output text 2>/dev/null || echo "unknown")"

  echo "--- simulate ec2:DescribeInstances (cluster role) ---"
  echo "EvalDecision=${decision}"
  if [ "${decision}" = "allowed" ]; then
    echo "RESULT: PASS — cluster role may call ec2:DescribeInstances."
    return 0
  fi

  echo "RESULT: FAIL — cluster role cannot ec2:DescribeInstances."
  echo "Fix: attach ec2:DescribeInstances to ${role_name} (global/policies eks_cluster policy)."
  echo "Then terraform apply global/policies and re-run dev nodes phase."

  local log_group="/aws/eks/${cluster_name}/cluster"
  local start_ms
  start_ms=$(( ($(date +%s) - 900) * 1000 ))
  if aws logs filter-log-events \
    --log-group-name "${log_group}" \
    --region "${AWS_REGION}" \
    --start-time "${start_ms}" \
    --filter-pattern "DescribeInstances" \
    --query 'events[-3:].message' \
    --output text 2>/dev/null | grep -q "DescribeInstances"; then
    echo "RESULT: FAIL — authenticator log confirms EC2 DescribeInstances denied for cluster role."
  fi
  return 1
}

# Print node join hints when a node group is CREATE_FAILED.
diagnose_node_join_failure() {
  tf_export_dev_vars
  local cluster_name="${1:-$(eks_cluster_name)}"
  local nodegroup_name="${2:-general}"
  local node_role_arn auth_mode
  local check1=0 check3=0 check4=0 check5=0

  echo "=== Node join diagnostics (${cluster_name}/${nodegroup_name}) ==="
  echo "Five-pillar debug: (1) aws-auth  (2) who writes it  (3) node IAM  (4) network  (5) cluster role EC2"

  aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.{authMode:accessConfig.authenticationMode,publicEndpoint:resourcesVpcConfig.endpointPublicAccess,privateEndpoint:resourcesVpcConfig.endpointPrivateAccess}' \
    --output json 2>/dev/null || true

  node_role_arn="$(node_iam_role_arn "${cluster_name}" 2>/dev/null || echo "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${cluster_name}-node")"
  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${AWS_REGION}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text 2>/dev/null || echo "unknown")"

  diag_node_join_check_aws_auth "${cluster_name}" "${node_role_arn}" "${auth_mode}" && check1=1 || check1=0
  diag_node_join_check_aws_auth_ownership "${cluster_name}" "${nodegroup_name}"
  diag_node_join_check_iam_policies "${node_role_arn}" && check3=1 || check3=0
  diag_node_join_check_network "${cluster_name}" "${nodegroup_name}" && check4=1 || check4=0
  diag_node_join_check_cluster_role_ec2 "${cluster_name}" && check5=1 || check5=0

  echo ""
  echo "========== CHECK 1b: EKS access entry (API_AND_CONFIG_MAP) =========="
  if aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${AWS_REGION}" &>/dev/null; then
    local entry_type
    entry_type="$(aws eks describe-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${AWS_REGION}" \
      --query 'accessEntry.type' \
      --output text 2>/dev/null || echo "unknown")"
    aws eks describe-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${AWS_REGION}" \
      --output json 2>/dev/null || true
    if [ "${auth_mode}" = "API_AND_CONFIG_MAP" ] && [ "${entry_type}" = "EC2_LINUX" ]; then
      echo "EKS EC2_LINUX access entry present (required with aws-auth mapRoles in API_AND_CONFIG_MAP)."
    fi
    echo "--- associated access policies for node role (EC2_LINUX entries cannot use these) ---"
    aws eks list-associated-access-policies \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${AWS_REGION}" \
      --output json 2>/dev/null || echo "(none or could not list)"
    if [ "${auth_mode}" = "API" ]; then
      echo "API + EC2_LINUX: node join uses the access entry only; IAM worker/CNI/ECR policies attach to the node role."
    fi
  else
    if [ "${auth_mode}" = "API" ]; then
      echo "::error::Node access entry missing — API mode requires EC2_LINUX entry for the node role."
    elif [ "${auth_mode}" = "API_AND_CONFIG_MAP" ]; then
      echo "(no access entry — EKS should create EC2_LINUX entry when the managed node group is created)"
    else
      echo "(no access entry for node role — OK for CONFIG_MAP + aws-auth only)"
    fi
  fi

  if [ "${auth_mode}" != "API" ]; then
    echo "--- RBAC node bindings (kubectl view; custom-columns may show <none>) ---"
    kubectl get clusterrolebinding system:node system:node-proxier system:node-bootstrapper \
      -o yaml 2>/dev/null | grep -E '^(  name:|    name: system:|    - system:)' \
      || echo "(could not read clusterrolebindings)"
  fi

  local log_group="/aws/eks/${cluster_name}/cluster"
  local start_ms
  start_ms=$(( ($(date +%s) - 900) * 1000 ))
  echo "--- authenticator log (last 15 min; deny/mapped/granted) ---"
  aws logs filter-log-events \
    --log-group-name "${log_group}" \
    --region "${AWS_REGION}" \
    --start-time "${start_ms}" \
    --filter-pattern "?access ?denied ?mapped ?granted ?Unauthorized" \
    --query 'events[-8:].message' \
    --output text 2>/dev/null \
    || echo "(no matching authenticator lines — check log group /aws/eks/${cluster_name}/cluster)"

  echo "--- authenticator: cluster role EC2 / {{EC2PrivateDNSName}} errors (last 15 min) ---"
  local auth_ec2_lines
  auth_ec2_lines="$(aws logs filter-log-events \
    --log-group-name "${log_group}" \
    --region "${AWS_REGION}" \
    --start-time "${start_ms}" \
    --filter-pattern "DescribeInstances" \
    --query 'events[-5:].message' \
    --output text 2>/dev/null || true)"
  if [ -n "${auth_ec2_lines}" ] && [ "${auth_ec2_lines}" != "None" ]; then
    printf '%s\n' "${auth_ec2_lines}"
    if printf '%s\n' "${auth_ec2_lines}" | grep -qE 'renderTemplates|private DNS|DescribeInstances'; then
      echo "RESULT: FAIL — cluster role lacks ec2:DescribeInstances (see CHECK 5)."
      check5=0
    fi
  else
    echo "(no DescribeInstances / renderTemplates lines in last 15 min)"
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

  echo ""
  echo "========== DEBUG CHECKLIST SUMMARY =========="
  echo "  CHECK 1 aws-auth mapRoles:        $([ "${check1}" -eq 1 ] && echo PASS || echo FAIL — see CHECK 1 above)"
  echo "  CHECK 2 aws-auth ownership:     see CHECK 2 (EKS on node group create; CI repair fallback)"
  echo "  CHECK 3 node IAM policies:      $([ "${check3}" -eq 1 ] && echo PASS || echo FAIL — see CHECK 3 above)"
  echo "  CHECK 4 network path:           $([ "${check4}" -eq 1 ] && echo PASS/WARN || echo WARN — see CHECK 4 above)"
  echo "  CHECK 5 cluster role EC2:       $([ "${check5}" -eq 1 ] && echo PASS || echo FAIL — ec2:DescribeInstances for {{EC2PrivateDNSName}})"
  echo "  Access entry + kubelet/instance: see sections below"
  echo ""
  echo "Copy this entire block from '=== Node join diagnostics' through this summary when asking for help."
}

# Scale down / delete node group before terraform destroy (faster, fewer timeouts).
dev_stack_destroy_prep() {
  tf_export_dev_vars
  local cluster_name nodegroup_name status
  cluster_name="$(eks_cluster_name)"
  nodegroup_name="general"

  if [ "${DEV_EKS_PHASE:-}" = "addons-only" ]; then
    echo "dev_eks_phase=addons-only: skipping node group teardown (add-ons-only destroy)."
    log_eks_addon_lifecycle destroy
    return 0
  fi

  if dev_stack_enable_addons; then
    log_eks_addon_lifecycle destroy
  fi

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
    if [ "${state_key}" = "$(bootstrap_state_s3_key)" ]; then
      bootstrap_clear_stale_s3_bootstrap_state || true
      # Do not upload an empty placeholder for bootstrap; prepare_bootstrap_destroy imports real resources.
    else
      ensure_remote_state_object_exists "${state_key}" || true
    fi
    if aws s3api head-object --bucket "${bucket}" --key "${state_key}" --region "${AWS_REGION}" &>/dev/null; then
      sync_terraform_state_digest_from_s3 "${bucket}" "${state_key}" "${table}" || true
    fi
  done
}

# After dev/policies destroy, drop their state objects so bootstrap can delete the bucket.
remove_downstream_remote_state_keys() {
  bootstrap_recover_kms || true
  resolve_bootstrap_backend_env "$(bootstrap_dir_abs global/bootstrap)" || return 0
  local bucket="${TF_BACKEND_BUCKET}"

  if ! aws s3api head-bucket --bucket "${bucket}" --region "${AWS_REGION}" 2>/dev/null; then
    return 0
  fi

  echo "Removing dev/policies state objects from ${bucket} (bootstrap state kept until bootstrap teardown)..."
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
  bootstrap_recover_kms_required || return 1
  repair_remote_state_backend_for_destroy
  bootstrap_init "${bootstrap_abs}"
  echo "Importing bootstrap resources into state (recovery after partial destroy)..."
  import_existing_bootstrap_resources "${bootstrap_abs}"
}

# Destroy bootstrap with safe ordering: dependents first, empty bucket, local state, then bucket/KMS.
bootstrap_terraform_destroy() {
  local bootstrap_dir="${1:-global/bootstrap}"
  local bootstrap_abs bucket rc
  bootstrap_abs="$(bootstrap_dir_abs "${bootstrap_dir}")"
  bucket="$(bootstrap_state_bucket_name)"

  bootstrap_recover_kms_required || return 1
  clear_s3_state_lockfiles "${bucket}"

  pushd "${bootstrap_abs}" >/dev/null
  mapfile -t var_args < <(tf_var_args)
  mapfile -t destroy_args < <(bootstrap_destroy_var_args)

  for target in \
    aws_dynamodb_table.terraform_state_lock \
    aws_s3_bucket_versioning.terraform_state \
    aws_s3_bucket_server_side_encryption_configuration.terraform_state \
    aws_s3_bucket_public_access_block.terraform_state; do
    echo "Destroying ${target} before bucket/KMS..."
    terraform destroy -input=false -auto-approve -no-color \
      -target="${target}" \
      "${var_args[@]}" "${destroy_args[@]}" || true
  done

  bootstrap_recover_kms_required || return 1
  popd >/dev/null

  bootstrap_switch_to_local_state_for_teardown "${bootstrap_dir}" || return 1

  pushd "${bootstrap_abs}" >/dev/null
  echo "Final bootstrap destroy from local state (bucket empty, no remote state writes)..."
  terraform destroy -input=false -auto-approve -no-color \
    "${var_args[@]}" "${destroy_args[@]}"
  rc=$?
  popd >/dev/null
  return "${rc}"
}

# Final cleanup when bucket, alias, or KMS key remain after destroy.
bootstrap_post_destroy_cleanup() {
  local bucket kms_alias key_id state

  tf_common_vars
  bucket="$(bootstrap_state_bucket_name)"
  kms_alias="$(bootstrap_kms_alias_name)"

  bootstrap_recover_kms || true

  if bootstrap_state_bucket_exists; then
    echo "State bucket still exists; removing all versioned objects..."
    bootstrap_empty_state_bucket_all_versions "${bucket}"
    clear_s3_state_lockfiles "${bucket}"
    aws s3api delete-bucket --bucket "${bucket}" --region "${AWS_REGION}" 2>/dev/null \
      && echo "Deleted bucket ${bucket}." \
      || echo "::warning::Could not delete bucket ${bucket}; delete manually." >&2
  fi

  if bootstrap_kms_alias_exists; then
    aws kms delete-alias --alias-name "${kms_alias}" --region "${AWS_REGION}" 2>/dev/null || true
    echo "Deleted KMS alias ${kms_alias}."
  fi

  if key_id="$(bootstrap_resolve_kms_key_id 2>/dev/null)"; then
    state="$(aws kms describe-key --key-id "${key_id}" \
      --region "${AWS_REGION}" \
      --query 'KeyMetadata.KeyState' --output text 2>/dev/null || true)"
    case "${state}" in
      Enabled)
        echo "Scheduling KMS key ${key_id} for deletion (7 day window)..."
        aws kms schedule-key-deletion \
          --key-id "${key_id}" \
          --pending-window-in-days 7 \
          --region "${AWS_REGION}" 2>/dev/null \
          || echo "::warning::Could not schedule KMS key deletion for ${key_id}." >&2
        ;;
      Disabled)
        echo "Enabling disabled KMS key ${key_id} before scheduling deletion..."
        aws kms enable-key --key-id "${key_id}" --region "${AWS_REGION}" 2>/dev/null || true
        bootstrap_wait_kms_key_enabled "${key_id}" || true
        aws kms schedule-key-deletion \
          --key-id "${key_id}" \
          --pending-window-in-days 7 \
          --region "${AWS_REGION}" 2>/dev/null \
          || echo "::warning::Could not schedule KMS key deletion for ${key_id}." >&2
        ;;
      PendingDeletion)
        echo "KMS key ${key_id} is already PendingDeletion."
        ;;
      *)
        echo "KMS key ${key_id} state: ${state:-unknown}"
        ;;
    esac
  fi
}

# Full bootstrap teardown for CI: prepare, destroy, post-cleanup.
bootstrap_finish_teardown() {
  local bootstrap_dir="${1:-global/bootstrap}"

  prepare_bootstrap_destroy || return 1
  bootstrap_terraform_destroy "${bootstrap_dir}" || {
    echo "::warning::Terraform destroy failed; running post-destroy cleanup..."
    bootstrap_post_destroy_cleanup
    return 1
  }
  bootstrap_post_destroy_cleanup
}

# Prepare dev stack before plan/apply (init + cluster recovery + auth mode).
dev_stack_prepare() {
  local dev_abs="${1:-environments/dev}"
  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_init_s3_backend "${dev_abs}" dev/terraform.tfstate

  if ! dev_stack_enable_eks_cluster; then
    echo "EKS phases off; provisioning VPC, IAM roles, and security groups only."
    return 0
  fi

  if ! dev_stack_enable_eks_nodes; then
    echo "EKS phase: cluster only (control plane, OIDC, vpc-cni; no node groups yet)."
    import_eks_foundation_resources "${dev_abs}"
    return 0
  fi

  recover_eks_cluster_before_apply "${dev_abs}"
  upgrade_eks_authentication_mode_if_needed
  cleanup_stale_eks_auth_state "${dev_abs}"
  import_eks_node_access_to_state "${dev_abs}"
  apply_eks_public_endpoint_if_needed "${dev_abs}"
  reset_stale_eks_managed_nodegroup
  delete_failed_eks_node_groups "${dev_abs}"
  repair_dev_node_join_if_needed "${dev_abs}"

  if dev_stack_enable_addons; then
    log_eks_addon_lifecycle apply
  fi
}

# Import cluster-level EKS resources (log group, OIDC, vpc-cni) when AWS has them but state was cleared.
import_eks_foundation_resources() {
  local dev_abs="${1:-environments/dev}"
  local cluster_name eks_prefix log_group_name
  local oidc_issuer oidc_provider_arn
  local did_pushd=false

  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars

  if ! dev_stack_enable_eks_cluster; then
    return 0
  fi

  cluster_name="$(eks_cluster_name)"
  eks_prefix="$(dev_eks_state_prefix)"
  log_group_name="/aws/eks/${cluster_name}/cluster"

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

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
    import_if_missing "${eks_prefix}.aws_cloudwatch_log_group.cluster" "${log_group_name}" true
  fi

  if eks_cluster_exists_in_aws "${cluster_name}"; then
    oidc_issuer="$(aws eks describe-cluster --name "${cluster_name}" --region "${AWS_REGION}" --query 'cluster.identity.oidc.issuer' --output text)"
    if [ -n "${oidc_issuer}" ] && [ "${oidc_issuer}" != "None" ]; then
      oidc_provider_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${oidc_issuer#https://}"
      if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${oidc_provider_arn}" &>/dev/null; then
        import_if_missing "${eks_prefix}.aws_iam_openid_connect_provider.cluster" "${oidc_provider_arn}" true
      fi
    fi

    import_if_missing "${eks_prefix}.aws_eks_addon.vpc_cni" "${cluster_name}:vpc-cni" true

    # EKS creates control-plane ↔ cluster SG rules at cluster create; drop stale TF addresses.
    for addr in \
      "${eks_prefix}.aws_vpc_security_group_ingress_rule.control_plane_from_cluster_sg_https" \
      "${eks_prefix}.aws_vpc_security_group_egress_rule.control_plane_to_cluster_sg_kubelet" \
      "${eks_prefix}.aws_vpc_security_group_egress_rule.control_plane_to_cluster_sg_webhooks"; do
      if terraform_state_has "${addr}"; then
        echo "Removing deprecated EKS cluster SG rule from state (managed by AWS): ${addr}"
        terraform state rm -no-color "${addr}" || true
      fi
    done
  fi

  if [ "${did_pushd}" = true ]; then
    popd >/dev/null
  fi
}

# Import dev/EKS resources that exist in AWS but are missing from state (partial apply recovery).
import_existing_dev_resources() {
  local dev_abs="${1:-environments/dev}"
  dev_abs="$(resolve_dev_dir "${dev_abs}")"
  tf_export_dev_vars

  import_eks_foundation_resources "${dev_abs}"

  if ! dev_stack_enable_eks_nodes; then
    echo "EKS nodes phase off; skipping node group and add-on imports."
    return 0
  fi

  local cluster_name eks_prefix addons_prefix
  cluster_name="$(eks_cluster_name)"
  eks_prefix="$(dev_eks_state_prefix)"
  addons_prefix="$(dev_addons_state_prefix)"
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

  local addon_name addon_addr
  for addon_name in kube-proxy coredns aws-ebs-csi-driver; do
    case "${addon_name}" in
      kube-proxy) addon_addr="${addons_prefix}.aws_eks_addon.kube_proxy" ;;
      coredns) addon_addr="${addons_prefix}.aws_eks_addon.coredns" ;;
      aws-ebs-csi-driver) addon_addr="${addons_prefix}.aws_eks_addon.aws_ebs_csi_driver" ;;
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
      "${eks_prefix}.aws_eks_node_group.main[\"${nodegroup_name}\"]" \
      "${cluster_name}:${nodegroup_name}" \
      true
  fi

  popd >/dev/null
}

# Managed resources only (excludes data sources; matches terraform apply counts).
dev_stack_managed_state_list() {
  terraform state list -no-color 2>/dev/null | grep -vE '^data\.|\.data\.' || true
}

# Map a Terraform state address to a summary category.
dev_stack_state_category() {
  local addr="${1:?}"

  case "${addr}" in
    module.vpc.module.vpc_endpoints.* \
      | module.vpc.aws_security_group.vpc_endpoints \
      | module.vpc.aws_vpc_security_group.vpc_endpoints* \
      | module.vpc.aws_vpc_security_group_ingress_rule.vpc_endpoints* \
      | module.vpc.aws_vpc_security_group_egress_rule.vpc_endpoints*)
      printf '%s' vpc_endpoints
      ;;
    module.vpc.*)
      printf '%s' vpc
      ;;
    module.iam_irsa.* | module.iam_irsa\[0\].* | module.iam.aws_iam_role.irsa* | module.iam.aws_iam_role_policy_attachment.irsa*)
      printf '%s' irsa
      ;;
    module.iam.*)
      printf '%s' iam
      ;;
    module.sg.*)
      printf '%s' security_groups
      ;;
    module.eks.* | module.eks\[0\].*)
      printf '%s' eks
      ;;
    module.addons.* | module.addons\[0\].*)
      printf '%s' addons
      ;;
    *)
      printf '%s' other
      ;;
  esac
}

# Print categorized resource counts and key outputs after dev apply.
dev_stack_apply_summary() {
  local dev_abs="${1:-environments/dev}"
  local did_pushd=false
  local addr category label
  local -a categories=(vpc vpc_endpoints iam security_groups eks irsa addons other)
  local -A category_labels=(
    [vpc]="VPC and networking"
    [vpc_endpoints]="VPC endpoints"
    [iam]="IAM roles and attachments"
    [security_groups]="EKS security groups and rules"
    [eks]="EKS cluster and node groups"
    [irsa]="IRSA roles"
    [addons]="EKS add-ons"
    [other]="Other"
  )
  local -A category_counts=()
  local -A category_items=()
  local total=0

  dev_abs="$(resolve_dev_dir "${dev_abs}")"

  if [ "$(pwd)" != "${dev_abs}" ]; then
    pushd "${dev_abs}" >/dev/null
    did_pushd=true
  fi

  echo "=== Dev stack apply summary ==="
  echo ""

  if ! dev_stack_managed_state_list | grep -q .; then
    echo "(no Terraform state — apply may not have completed)"
    if [ "${did_pushd}" = true ]; then
      popd >/dev/null
    fi
    return 0
  fi

  while IFS= read -r addr; do
    [ -z "${addr}" ] && continue
    category="$(dev_stack_state_category "${addr}")"
    category_counts["${category}"]=$(( ${category_counts["${category}"]:-0} + 1 ))
    category_items["${category}"]+="${addr}"$'\n'
    total=$((total + 1))
  done < <(dev_stack_managed_state_list)

  echo "Total managed resources: ${total} (data sources excluded)"
  echo ""

  for category in "${categories[@]}"; do
    [ "${category_counts[${category}]:-0}" -eq 0 ] && continue
    label="${category_labels[${category}]}"
    echo "${label}: ${category_counts[${category}]}"
    while IFS= read -r addr; do
      [ -z "${addr}" ] && continue
      echo "  - ${addr}"
    done <<< "${category_items[${category}]}"
    echo ""
  done

  echo "--- Key outputs ---"
  for output in enable_eks enable_eks_cluster enable_eks_nodes enable_irsa enable_addons \
    vpc_id public_subnet_ids private_subnet_ids \
    cluster_role_arn node_role_arn control_plane_sg_id node_sg_id \
    kms_key_arn cluster_name cluster_endpoint oidc_provider_arn \
    node_group_ids irsa_role_arns addon_arns; do
    if terraform output -no-color "${output}" &>/dev/null; then
      echo "${output} = $(terraform output -no-color "${output}" 2>/dev/null || true)"
    fi
  done

  if dev_stack_enable_addons; then
    echo ""
    log_eks_addon_lifecycle apply
  fi

  if [ "${did_pushd}" = true ]; then
    popd >/dev/null
  fi
}
