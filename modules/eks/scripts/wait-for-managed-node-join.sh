#!/usr/bin/env bash
# After managed node group create: verify EKS access entry + aws-auth, then wait for Ready.
set -euo pipefail

wait_for_managed_node_join() {
  local cluster_name="${CLUSTER_NAME:?}"
  local nodegroup_name="${NODEGROUP_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local desired_size="${DESIRED_SIZE:-1}"
  local script_dir auth_mode

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"

  echo "Managed node join check (auth=${auth_mode}, nodegroup=${nodegroup_name})..."

  if [ "${auth_mode}" = "API_AND_CONFIG_MAP" ] || [ "${auth_mode}" = "API" ]; then
    CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
      bash "${script_dir}/wait-for-node-access-entry.sh" || {
        echo "::warning::EKS access entry not present yet; continuing (aws-auth may still work in API_AND_CONFIG_MAP)."
      }
  fi

  if [ "${auth_mode}" = "API_AND_CONFIG_MAP" ] || [ "${auth_mode}" = "CONFIG_MAP" ]; then
    if ! kubectl get configmap aws-auth -n kube-system -o yaml 2>/dev/null | grep -Fq "${node_role_arn}"; then
      echo "Node role missing from aws-auth; merging mapRoles..."
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
        bash "${script_dir}/prepare-managed-node-aws-auth.sh"
    fi
  fi

  # Node group create: Ready is enough. CCM init (topology labels) is gated before add-ons only.
  CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
    NODEGROUP_NAME="${nodegroup_name}" DESIRED_SIZE="${desired_size}" REQUIRE_CCM_INIT=false \
    bash "${script_dir}/wait-for-ready-nodes.sh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  wait_for_managed_node_join
fi
