#!/usr/bin/env bash
# Pre-nodegroup: aws-auth for managed nodes (remove stale CLI access entries in API_AND_CONFIG_MAP).
set -euo pipefail

ensure_node_cluster_auth() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
    bash "${script_dir}/prepare-managed-node-aws-auth.sh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ensure_node_cluster_auth
fi
