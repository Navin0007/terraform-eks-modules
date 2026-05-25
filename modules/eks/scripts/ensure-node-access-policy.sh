#!/usr/bin/env bash
# EC2_LINUX entries need AmazonEKSNodegroupPolicy or kubelet stays Unauthorized.
set -euo pipefail

NODEGROUP_POLICY_ARN="arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodegroupPolicy"

ensure_node_access_policy() {
  local cluster_name="${CLUSTER_NAME:?}"
  local node_role_arn="${NODE_ROLE_ARN:?}"
  local region="${AWS_REGION:?}"
  local associated

  if ! aws eks describe-access-entry \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${region}" &>/dev/null; then
    echo "::error::Node access entry missing; cannot associate ${NODEGROUP_POLICY_ARN}." >&2
    return 1
  fi

  associated="$(aws eks list-associated-access-policies \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --region "${region}" \
    --query "associatedAccessPolicies[?policyArn=='${NODEGROUP_POLICY_ARN}'].policyArn | [0]" \
    --output text 2>/dev/null || echo "None")"

  if [ "${associated}" = "${NODEGROUP_POLICY_ARN}" ]; then
    echo "AmazonEKSNodegroupPolicy already associated with node access entry."
    return 0
  fi

  echo "Associating AmazonEKSNodegroupPolicy with node access entry..."
  aws eks associate-access-policy \
    --cluster-name "${cluster_name}" \
    --principal-arn "${node_role_arn}" \
    --policy-arn "${NODEGROUP_POLICY_ARN}" \
    --access-scope "type=cluster" \
    --region "${region}"
  echo "AmazonEKSNodegroupPolicy associated."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ensure_node_access_policy
fi
