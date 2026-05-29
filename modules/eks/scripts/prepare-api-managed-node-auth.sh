#!/usr/bin/env bash
# Managed node groups: EKS must create the EC2_LINUX access entry when the node group
# is created. Remove stale entries that were created before the node group existed.
set -euo pipefail

prepare_api_managed_node_auth() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local nodegroup_name="${NODEGROUP_NAME:-general}"
  local script_dir auth_mode ng_status

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  auth_mode="$(aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text 2>/dev/null || echo "unknown")"

  [ "${auth_mode}" = "API" ] || return 0

  if ! aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${region}" &>/dev/null; then
    echo "API mode: no node access entry yet (EKS will create one with the managed node group)."
    return 0
  fi

  if ! aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}" &>/dev/null; then
    echo "API mode: removing pre-nodegroup access entry so EKS can recreate it with the node group..."
    CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
      bash "${script_dir}/delete-node-access-entry.sh"
    return 0
  fi

  ng_status="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}" \
    --query 'nodegroup.status' \
    --output text)"

  case "${ng_status}" in
    CREATE_FAILED|DEGRADED)
      echo "API mode: node group ${nodegroup_name} is ${ng_status}; resetting node group and access entry..."
      aws eks delete-nodegroup \
        --cluster-name "${cluster_name}" \
        --nodegroup-name "${nodegroup_name}" \
        --region "${region}" || true
      aws eks wait nodegroup-deleted \
        --cluster-name "${cluster_name}" \
        --nodegroup-name "${nodegroup_name}" \
        --region "${region}" || true
      CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
        bash "${script_dir}/delete-node-access-entry.sh"
      ;;
    ACTIVE)
      local desired ready
      desired="$(aws eks describe-nodegroup \
        --cluster-name "${cluster_name}" \
        --nodegroup-name "${nodegroup_name}" \
        --region "${region}" \
        --query 'nodegroup.scalingConfig.desiredSize' \
        --output text)"
      aws eks update-kubeconfig --name "${cluster_name}" --region "${region}" >/dev/null 2>&1 || true
      ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready" { n++ } END { print n + 0 }')"
      if [ "${desired:-0}" -gt 0 ] && [ "${ready:-0}" -eq 0 ]; then
        echo "API mode: node group ACTIVE with desired=${desired} but Ready nodes=0; resetting (stale pre-nodegroup access entry)."
        aws eks update-nodegroup-config \
          --cluster-name "${cluster_name}" \
          --nodegroup-name "${nodegroup_name}" \
          --region "${region}" \
          --scaling-config "minSize=0,maxSize=0,desiredSize=0" || true
        aws eks wait nodegroup-active \
          --cluster-name "${cluster_name}" \
          --nodegroup-name "${nodegroup_name}" \
          --region "${region}" || true
        aws eks delete-nodegroup \
          --cluster-name "${cluster_name}" \
          --nodegroup-name "${nodegroup_name}" \
          --region "${region}" || true
        aws eks wait nodegroup-deleted \
          --cluster-name "${cluster_name}" \
          --nodegroup-name "${nodegroup_name}" \
          --region "${region}" || true
        CLUSTER_NAME="${cluster_name}" NODE_ROLE_ARN="${node_role_arn}" AWS_REGION="${region}" \
          bash "${script_dir}/delete-node-access-entry.sh"
      else
        echo "API mode: node group ${nodegroup_name} is ACTIVE (Ready=${ready:-0}, desired=${desired:-0})."
      fi
      ;;
    *)
      echo "API mode: node group ${nodegroup_name} is ${ng_status}; keeping EKS-managed access entry."
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  prepare_api_managed_node_auth
fi
