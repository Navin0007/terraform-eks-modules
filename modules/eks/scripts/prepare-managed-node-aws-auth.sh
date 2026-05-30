#!/usr/bin/env bash
# Fallback: merge node role into aws-auth mapRoles (never delete EKS access entries).
# EKS should create access entry + aws-auth when the managed node group is created.
set -euo pipefail

prepare_managed_node_aws_auth() {
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

  case "${auth_mode}" in
    API)
      echo "::error::API authentication mode is unsupported for managed node groups (use API_AND_CONFIG_MAP)." >&2
      return 1
      ;;
    CONFIG_MAP | API_AND_CONFIG_MAP)
      echo "Merging node role into aws-auth mapRoles (fallback; EKS should manage this on node group create)..."
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
        python3 "${script_dir}/merge-aws-auth-maproles.py"
      ;;
    *)
      echo "::error::Unsupported authentication mode: ${auth_mode}" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  prepare_managed_node_aws_auth
fi
