#!/usr/bin/env bash
set -euo pipefail

count_ccm_initialized_nodes() {
  local desired_size="${1:-1}"

  kubectl get nodes -o json 2>/dev/null | python3 -c "
import json, sys

desired = int('${desired_size}')
data = json.load(sys.stdin)
ready = 0

for node in data.get('items', []):
    conditions = {
        c['type']: c['status']
        for c in node.get('status', {}).get('conditions', [])
    }
    if conditions.get('Ready') != 'True':
        continue

    taints = node.get('spec', {}).get('taints') or []
    if any(t.get('key') == 'node.cloudprovider.kubernetes.io/uninitialized' for t in taints):
        continue

    labels = node.get('metadata', {}).get('labels', {})
    if not labels.get('topology.kubernetes.io/zone'):
        continue
    if not labels.get('node.kubernetes.io/instance-type'):
        continue

    ready += 1

print(ready)
" 2>/dev/null || echo "0"
}

wait_for_ready_nodes() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local desired_size="${DESIRED_SIZE:-1}"
  local require_ccm_init="${REQUIRE_CCM_INIT:-true}"
  local script_dir attempt ready total ccm_ready

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  aws eks describe-cluster \
    --name "${cluster_name}" \
    --region "${region}" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text >/dev/null

  aws eks update-kubeconfig --name "${cluster_name}" --region "${region}" >/dev/null

  for attempt in $(seq 1 45); do
    ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready" { n++ } END { print n + 0 }')"
    total="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    ccm_ready="$(count_ccm_initialized_nodes "${desired_size}")"

    if [ "${require_ccm_init}" = "true" ]; then
      echo "Node join check ${attempt}/45: Ready=${ready}/${total} (want >= ${desired_size}), CCM-initialized=${ccm_ready}/${desired_size}"
    else
      echo "Node join check ${attempt}/45: Ready=${ready}/${total} (want >= ${desired_size})"
    fi

    aws eks describe-nodegroup \
      --cluster-name "${cluster_name}" \
      --nodegroup-name "${NODEGROUP_NAME:-general}" \
      --region "${region}" \
      --query 'nodegroup.{status:status,desired:scalingConfig.desiredSize,health:health}' \
      --output json 2>/dev/null || true
    kubectl get nodes -o custom-columns=\
NAME:.metadata.name,READY:.status.conditions[-1].type,TAINTS:.spec.taints[*].key,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone,TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type \
      2>/dev/null || echo "(kubectl get nodes failed or no nodes)"

    if [ "${ready}" -ge "${desired_size}" ] && [ "${ready}" -gt 0 ]; then
      if [ "${require_ccm_init}" != "true" ] || [ "${ccm_ready}" -ge "${desired_size}" ]; then
        if [ "${require_ccm_init}" = "true" ]; then
          echo "Nodes are Ready and CCM-initialized (topology labels set, uninitialized taint removed)."
        else
          echo "Nodes are Ready."
        fi
        return 0
      fi
    fi

    sleep 20
  done

  if [ "${require_ccm_init}" = "true" ]; then
    echo "::error::Timed out waiting for ${desired_size} CCM-initialized node(s) (Ready + no uninitialized taint + topology labels)." >&2
  else
    echo "::error::Timed out waiting for ${desired_size} Ready node(s)." >&2
  fi
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  wait_for_ready_nodes
fi
