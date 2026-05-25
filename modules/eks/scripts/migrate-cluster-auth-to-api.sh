#!/usr/bin/env bash
# API-only auth: node IAM roles use EC2_LINUX access entries (not aws-auth).
set -euo pipefail

migrate_cluster_auth_to_api() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local mode update_id status

  mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"

  if [ "${mode}" = "API" ]; then
    echo "Cluster authentication mode is already API."
    return 0
  fi

  if [ "${mode}" != "API_AND_CONFIG_MAP" ]; then
    echo "::error::Cannot migrate authentication mode from ${mode} to API." >&2
    return 1
  fi

  echo "Migrating cluster authentication mode API_AND_CONFIG_MAP → API..."
  update_id="$(aws eks update-cluster-config \
    --name "${cluster_name}" \
    --region "${region}" \
    --access-config "authenticationMode=API" \
    --query 'update.id' \
    --output text)"

  while true; do
    status="$(aws eks describe-update \
      --name "${cluster_name}" \
      --region "${region}" \
      --update-id "${update_id}" \
      --query 'update.status' \
      --output text)"
    case "${status}" in
      Successful) break ;;
      Failed)
        echo "::error::Authentication mode migration to API failed." >&2
        return 1
        ;;
      *)
        echo "Waiting for API authentication mode (${status})..."
        sleep 10
        ;;
    esac
  done

  aws eks wait cluster-active --name "${cluster_name}" --region "${region}"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
    bash "${SCRIPT_DIR}/delete-node-access-entry.sh" || true

  if ! aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${region}" &>/dev/null; then
    echo "Creating EC2_LINUX access entry for node role (API mode)..."
    aws eks create-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --type EC2_LINUX \
      --region "${region}"
  fi

  mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"
  echo "Cluster authentication mode is now ${mode}."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate_cluster_auth_to_api
fi
