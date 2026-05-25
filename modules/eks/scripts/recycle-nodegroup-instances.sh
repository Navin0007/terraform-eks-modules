#!/usr/bin/env bash
# Terminate existing node group instances so new ones pick up API/EC2_LINUX auth.
set -euo pipefail

recycle_nodegroup_instances() {
  local cluster_name="${CLUSTER_NAME:?}"
  local nodegroup_name="${NODEGROUP_NAME:-general}"
  local region="${AWS_REGION:?}"
  local asg_name iid

  if ! aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}" &>/dev/null; then
    echo "Node group ${nodegroup_name} not found; nothing to recycle."
    return 0
  fi

  asg_name="$(aws eks describe-nodegroup \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}" \
    --query 'nodegroup.resources.autoScalingGroups[0].name' \
    --output text 2>/dev/null || echo "None")"

  if [ -z "${asg_name}" ] || [ "${asg_name}" = "None" ]; then
    echo "No ASG for node group ${nodegroup_name}; nothing to recycle."
    return 0
  fi

  mapfile -t instances < <(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "${asg_name}" \
    --region "${region}" \
    --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
    --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d')

  if [ "${#instances[@]}" -eq 0 ]; then
    echo "No running instances in ${asg_name}."
    return 0
  fi

  echo "Recycling ${#instances[@]} instance(s) in ${nodegroup_name} (auth/config change)..."
  aws ec2 terminate-instances --instance-ids "${instances[@]}" --region "${region}" >/dev/null

  echo "Waiting for node group to become ACTIVE after instance recycle..."
  aws eks wait nodegroup-active \
    --cluster-name "${cluster_name}" \
    --nodegroup-name "${nodegroup_name}" \
    --region "${region}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  recycle_nodegroup_instances
fi
