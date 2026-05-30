#!/usr/bin/env bash
# Node group at scale 0, remove access entries, refresh aws-auth, scale out, verify Ready.
set -euo pipefail

after_nodegroup_auth() {
  local cluster_name="${CLUSTER_NAME:?}"
  local nodegroup_name="${NODEGROUP_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local desired_size="${DESIRED_SIZE:?}"
  local min_size="${MIN_SIZE:?}"
  local max_size="${MAX_SIZE:?}"
  local script_dir auth_mode

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"

  if [ "${auth_mode}" = "API" ]; then
    echo "::error::Cluster is in API authentication mode; managed node groups require API_AND_CONFIG_MAP." >&2
    echo "::error::Re-run apply — CI will recreate the cluster (recover_dev_cluster_if_api_mode)." >&2
    exit 1
  fi

  echo "Waiting for node group ${nodegroup_name} to become ACTIVE (scale 0)..."
  aws eks wait nodegroup-active \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}"

  echo "Ensuring EC2_LINUX access entry and aws-auth before scaling node group..."
  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
    NODEGROUP_NAME="${nodegroup_name}" \
    bash "${script_dir}/ensure-node-access-entry.sh"
  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
    python3 "${script_dir}/merge-aws-auth-maproles.py"

  echo "Scaling node group ${nodegroup_name} to desired=${desired_size}, min=${min_size}, max=${max_size}..."
  aws eks update-nodegroup-config \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}" \
    --scaling-config "minSize=${min_size},maxSize=${max_size},desiredSize=${desired_size}"

  echo "Waiting for node group after scale-out..."
  aws eks wait nodegroup-active \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}"

  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
    NODEGROUP_NAME="${nodegroup_name}" DESIRED_SIZE="${desired_size}" \
    bash "${script_dir}/wait-for-ready-nodes.sh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  after_nodegroup_auth
fi
