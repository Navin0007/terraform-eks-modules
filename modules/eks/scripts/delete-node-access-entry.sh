#!/usr/bin/env bash
# Remove EKS access entries for the node IAM role (managed nodes use aws-auth only).
set -euo pipefail

delete_node_access_entry() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local attempt entry_type

  for attempt in 1 2 3 4 5; do
    if ! aws eks describe-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${region}" &>/dev/null; then
      echo "No access entry for node role (OK for managed nodes + aws-auth)."
      return 0
    fi

    entry_type="$(aws eks describe-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${region}" \
      --query 'accessEntry.type' \
      --output text)"

    echo "Deleting ${entry_type} access entry for ${node_role_arn} (attempt ${attempt})..."
    aws eks delete-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${region}"
    sleep 5
  done

  if aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${region}" &>/dev/null; then
    echo "::error::Node access entry still exists after delete retries." >&2
    return 1
  fi

  echo "Node access entry removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  delete_node_access_entry
fi
