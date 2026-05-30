#!/usr/bin/env bash
# Managed node groups join via aws-auth mapRoles (CONFIG_MAP, or API_AND_CONFIG_MAP without access entries).
# CLI-created EC2_LINUX access entries take API auth precedence and break join when
# EKS did not create the entry; remove any stale entry so aws-auth is used.
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
      echo "::error::API authentication mode is unsupported for managed node groups (use CONFIG_MAP + aws-auth)." >&2
      return 1
      ;;
    CONFIG_MAP | API_AND_CONFIG_MAP)
      if aws eks describe-access-entry \
        --cluster-name "${cluster_name}" \
        --principal-arn "${node_role_arn}" \
        --region "${region}" &>/dev/null; then
        echo "Removing node access entry so managed nodes authenticate via aws-auth (CLI entries block join)..."
        CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
          bash "${script_dir}/delete-node-access-entry.sh"
      else
        echo "No node access entry present (managed nodes will use aws-auth mapRoles)."
      fi
      echo "Merging node role into aws-auth mapRoles..."
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
