#!/usr/bin/env bash
# API-only auth: migrate cluster mode; EC2_LINUX access entry is ensured separately.
set -euo pipefail

migrate_cluster_auth_to_api() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local mode update_id status script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"

  if [ "${mode}" = "API" ]; then
    echo "Cluster authentication mode is already API."
    CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
      bash "${script_dir}/ensure-node-cluster-auth.sh"
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

  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
    bash "${script_dir}/ensure-node-cluster-auth.sh"

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
