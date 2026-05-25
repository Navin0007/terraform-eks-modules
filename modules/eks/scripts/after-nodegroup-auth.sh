#!/usr/bin/env bash
# Node group is created at scale 0 so we can drop API access entries before instances launch.
set -euo pipefail

after_nodegroup_auth() {
  local cluster_name="${CLUSTER_NAME:?}"
  local nodegroup_name="${NODEGROUP_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local desired_size="${DESIRED_SIZE:?}"
  local min_size="${MIN_SIZE:?}"
  local max_size="${MAX_SIZE:?}"
  local script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  echo "Waiting for node group ${nodegroup_name} to become ACTIVE (scale 0)..."
  aws eks wait nodegroup-active \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}"

  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
    bash "${script_dir}/delete-node-access-entry.sh"

  echo "Refreshing aws-auth before scaling node group..."
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
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  after_nodegroup_auth
fi
