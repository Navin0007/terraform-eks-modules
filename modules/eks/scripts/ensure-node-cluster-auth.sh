#!/usr/bin/env bash
# Ensure managed node IAM role can join the cluster (auth mode aware).
set -euo pipefail

ensure_node_cluster_auth() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local auth_mode repo_root script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/../../.." && pwd)"

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text 2>/dev/null || echo "CONFIG_MAP")"

  echo "EKS authentication mode: ${auth_mode}"

  # EC2_LINUX access entries break managed node join when API is evaluated first.
  if aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${region}" &>/dev/null; then
    entry_type="$(aws eks describe-access-entry \
      --cluster-name "${cluster_name}" \
      --principal-arn "${node_role_arn}" \
      --region "${region}" \
      --query 'accessEntry.type' \
      --output text)"
    if [ "${entry_type}" = "EC2_LINUX" ]; then
      echo "Deleting EC2_LINUX access entry for managed node role ${node_role_arn}..."
      aws eks delete-access-entry \
        --cluster-name "${cluster_name}" \
        --principal-arn "${node_role_arn}" \
        --region "${region}"
    fi
  fi

  case "${auth_mode}" in
    API)
      echo "API mode: creating STANDARD access entry for node role..."
      if ! aws eks describe-access-entry \
        --cluster-name "${cluster_name}" \
        --principal-arn "${node_role_arn}" \
        --region "${region}" &>/dev/null; then
        aws eks create-access-entry \
          --cluster-name "${cluster_name}" \
          --principal-arn "${node_role_arn}" \
          --type STANDARD \
          --username "system:node:{{EC2PrivateDNSName}}" \
          --kubernetes-groups system:bootstrappers system:nodes \
          --region "${region}"
      else
        echo "Access entry already exists for ${node_role_arn}."
      fi
      ;;
    API_AND_CONFIG_MAP | CONFIG_MAP)
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
