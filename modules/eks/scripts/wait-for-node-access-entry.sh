#!/usr/bin/env bash
# After a managed node group exists, EKS creates the EC2_LINUX access entry in API mode.
set -euo pipefail

wait_for_node_access_entry() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local attempt

  for attempt in $(seq 1 30); do
    if aws eks describe-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${region}" &>/dev/null; then
      aws eks describe-access-entry \
        --cluster-name "${cluster_name}" \
        --principal-arn "${node_role_arn}" \
        --region "${region}" \
        --output json
      echo "Node access entry is present (attempt ${attempt})."
      return 0
    fi
    echo "Waiting for EKS to create node access entry (${attempt}/30)..."
    sleep 10
  done

  echo "::error::Timed out waiting for EKS to create EC2_LINUX access entry for ${node_role_arn}." >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  wait_for_node_access_entry
fi
