#!/usr/bin/env bash
# Pre-nodegroup: aws-auth only for API_AND_CONFIG_MAP (no node access entries).
set -euo pipefail

ensure_node_cluster_auth() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local auth_mode script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text 2>/dev/null || echo "CONFIG_MAP")"

  echo "EKS authentication mode: ${auth_mode}"

  case "${auth_mode}" in
    API)
      echo "API mode: ensuring EC2_LINUX access entry for node role..."
      if ! aws eks describe-access-entry \
        --cluster-name "${cluster_name}" \
        --principal-arn "${node_role_arn}" \
        --region "${region}" &>/dev/null; then
        aws eks create-access-entry \
          --cluster-name "${cluster_name}" \
          --principal-arn "${node_role_arn}" \
          --type EC2_LINUX \
          --region "${region}"
      fi
      echo "Node IAM permissions are via role policy attachments (not EKS access policies on EC2_LINUX entries)."
      ;;
    API_AND_CONFIG_MAP | CONFIG_MAP)
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
        bash "${script_dir}/delete-node-access-entry.sh"
      echo "Merging node role into aws-auth mapRoles..."
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
        python3 "${script_dir}/merge-aws-auth-maproles.py"
      ;;
    *)
      echo "::error::Unsupported authentication mode: ${auth_mode}"
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ensure_node_cluster_auth
fi
