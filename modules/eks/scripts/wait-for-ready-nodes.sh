#!/usr/bin/env bash
set -euo pipefail

wait_for_ready_nodes() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local desired_size="${DESIRED_SIZE:-1}"
  local script_dir attempt ready total

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local auth_mode

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"

  aws eks update-kubeconfig --name "${cluster_name}" --region "${region}" >/dev/null

  for attempt in $(seq 1 45); do
    if [ "${auth_mode}" = "API_AND_CONFIG_MAP" ]; then
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
        NODEGROUP_NAME="${NODEGROUP_NAME:-general}" \
        bash "${script_dir}/ensure-node-access-entry.sh" 2>/dev/null || true

      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
        python3 "${script_dir}/merge-aws-auth-maproles.py" 2>/dev/null || true
    elif [ "${auth_mode}" = "CONFIG_MAP" ]; then
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
        python3 "${script_dir}/merge-aws-auth-maproles.py" 2>/dev/null || true
    fi

    ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready" { n++ } END { print n + 0 }')"
    total="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"

    echo "Node join check ${attempt}/45: Ready=${ready}/${total} (want >= ${desired_size})"
    aws eks describe-nodegroup \
      --cluster-name "${cluster_name}" \
      --nodegroup-name "${NODEGROUP_NAME:-general}" \
      --region "${region}" \
      --query 'nodegroup.{status:status,desired:scalingConfig.desiredSize,health:health}' \
      --output json 2>/dev/null || true
    kubectl get nodes -o wide 2>/dev/null || echo "(kubectl get nodes failed or no nodes)"

    if [ "${ready}" -ge "${desired_size}" ] && [ "${ready}" -gt 0 ]; then
      echo "Nodes are Ready."
      return 0
    fi

    sleep 20
  done

  echo "::error::Timed out waiting for ${desired_size} Ready node(s)." >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  wait_for_ready_nodes
fi
