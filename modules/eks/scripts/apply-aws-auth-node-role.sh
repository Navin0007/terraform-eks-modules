#!/usr/bin/env bash
# Merge the node IAM role into kube-system/aws-auth mapRoles (managed node groups).
set -euo pipefail

apply_aws_auth_node_role() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"

  aws eks update-kubeconfig --name "${cluster_name}" --region "${region}" >/dev/null

  local current
  current="$(kubectl get configmap aws-auth -n kube-system -o jsonpath='{.data.mapRoles}' 2>/dev/null || true)"

  if [ -n "${current}" ] && echo "${current}" | grep -Fq "${node_role_arn}"; then
    echo "Node role already present in aws-auth mapRoles: ${node_role_arn}"
    return 0
  fi

  local entry
  entry="$(printf '%s\n' \
    "- rolearn: ${node_role_arn}" \
    "  username: system:node:{{EC2PrivateDNSName}}" \
    "  groups:" \
    "    - system:bootstrappers" \
    "    - system:nodes")"

  local merged="${entry}"
  if [ -n "${current}" ]; then
    merged="${current}"$'\n'"${entry}"
  fi

  local patch_json
  patch_json="$(python3 -c 'import json, os; print(json.dumps({"data": {"mapRoles": os.environ["MAP_ROLES"]}}))' \
    MAP_ROLES="${merged}")"

  if kubectl get configmap aws-auth -n kube-system &>/dev/null; then
    kubectl patch configmap aws-auth -n kube-system --type merge -p "${patch_json}"
  else
    kubectl create configmap aws-auth -n kube-system --from-literal=mapRoles="${merged}"
  fi

  echo "aws-auth mapRoles updated for ${node_role_arn}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  apply_aws_auth_node_role
fi
