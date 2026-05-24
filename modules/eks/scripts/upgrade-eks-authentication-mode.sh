#!/usr/bin/env bash
# Upgrade CONFIG_MAP → API_AND_CONFIG_MAP (required for aws_eks_access_entry).
# Invoked from CI or Terraform null_resource (CLUSTER_NAME + AWS_REGION).
set -euo pipefail

upgrade_eks_authentication_mode() {
  local cluster_name="$1"
  local region="$2"
  local mode update_id status

  mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text 2>/dev/null || echo "CONFIG_MAP")"

  if [ "${mode}" != "CONFIG_MAP" ]; then
    echo "EKS authentication mode is already ${mode}."
    return 0
  fi

  echo "Upgrading EKS authentication mode to API_AND_CONFIG_MAP..."
  update_id="$(aws eks update-cluster-config \
    --name "${cluster_name}" \
    --region "${region}" \
    --access-config "authenticationMode=API_AND_CONFIG_MAP" \
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
        aws eks describe-update \
          --name "${cluster_name}" \
          --region "${region}" \
          --update-id "${update_id}" \
          --output json >&2 || true
        echo "EKS authentication mode update failed." >&2
        return 1
        ;;
      *)
        echo "Waiting for authentication mode update (${status})..."
        sleep 10
        ;;
    esac
  done

  aws eks wait cluster-active --name "${cluster_name}" --region "${region}"

  for _ in $(seq 1 60); do
    mode="$(aws eks describe-cluster \
      --name "${cluster_name}" \
      --region "${region}" \
      --query 'cluster.accessConfig.authenticationMode' \
      --output text)"
    if [ "${mode}" = "API_AND_CONFIG_MAP" ] || [ "${mode}" = "API" ]; then
      echo "EKS authentication mode is now ${mode}."
      return 0
    fi
    echo "Waiting for authentication mode to become API_AND_CONFIG_MAP (current: ${mode})..."
    sleep 10
  done

  echo "Timed out waiting for authentication mode upgrade." >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  upgrade_eks_authentication_mode "${CLUSTER_NAME:?}" "${AWS_REGION:?}"
fi
