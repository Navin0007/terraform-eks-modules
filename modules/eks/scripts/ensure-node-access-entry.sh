#!/usr/bin/env bash
# API_AND_CONFIG_MAP managed nodes need the EKS EC2_LINUX access entry AND aws-auth mapRoles.
set -euo pipefail

ensure_node_access_entry() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local nodegroup_name="${NODEGROUP_NAME:-general}"
  local auth_mode attempt script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text 2>/dev/null || echo "CONFIG_MAP")"

  case "${auth_mode}" in
    API)
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
        bash "${script_dir}/wait-for-node-access-entry.sh"
      return $?
      ;;
    CONFIG_MAP)
      return 0
      ;;
    API_AND_CONFIG_MAP)
      ;;
    *)
      echo "::error::Unsupported authentication mode: ${auth_mode}" >&2
      return 1
      ;;
  esac

  if aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${region}" &>/dev/null; then
    aws eks describe-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${region}" \
      --output json
    echo "Node access entry already present."
    return 0
  fi

  if aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}" &>/dev/null; then
    echo "Waiting for EKS to create EC2_LINUX access entry for ${nodegroup_name}..."
    if CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
      bash "${script_dir}/wait-for-node-access-entry.sh"; then
      return 0
    fi
    echo "EKS did not create access entry; creating EC2_LINUX entry for managed node group..."
    aws eks create-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --type EC2_LINUX \
      --region "${region}"
    aws eks describe-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${region}" \
      --output json
    return 0
  fi

  echo "Node group ${nodegroup_name} not found yet; access entry will be ensured after it exists."
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ensure_node_access_entry
fi
