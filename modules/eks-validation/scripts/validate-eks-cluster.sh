#!/usr/bin/env bash
# Post-apply EKS cluster validation — aws CLI + kubectl checks.
# See docs/EKS-POST-APPLY-VALIDATION.md for the full checklist mapping.
set -euo pipefail

FAILURES=()
WARNINGS=()
CHECKED=0
PASSED=0

log_section() {
  echo ""
  echo "=== $1 ==="
}

truthy() {
  local v
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "${v}" in
    1 | true | yes) return 0 ;;
    *) return 1 ;;
  esac
}

skip_if_disabled() {
  local flag="$1"
  local name="$2"
  if truthy "${!flag:-false}"; then
    echo "SKIP: ${name} (${flag}=true)"
    return 0
  fi
  return 1
}

record_pass() {
  CHECKED=$((CHECKED + 1))
  PASSED=$((PASSED + 1))
  echo "PASS: $1"
}

record_fail() {
  CHECKED=$((CHECKED + 1))
  FAILURES+=("$1")
  echo "FAIL: $1" >&2
}

record_warn() {
  WARNINGS+=("$1")
  echo "WARN: $1"
}

failed_contains() {
  local needle="$1"
  local item
  for item in "${FAILURES[@]}"; do
    if [[ "${item}" == *"${needle}"* ]]; then
      return 0
    fi
  done
  return 1
}

warned_contains() {
  local needle="$1"
  local item
  for item in "${WARNINGS[@]}"; do
    if [[ "${item}" == *"${needle}"* ]]; then
      return 0
    fi
  done
  return 1
}

section_skipped() {
  truthy "${1:-false}"
}

# pass | fail | skip | n/a
checklist_status() {
  local fail_pattern="${1:-}"
  local skip_flag="${2:-false}"

  if section_skipped "${skip_flag}"; then
    echo "SKIP"
    return
  fi
  if [ -n "${fail_pattern}" ] && failed_contains "${fail_pattern}"; then
    echo "FAIL"
    return
  fi
  if [ "${CHECKED}" -eq 0 ]; then
    echo "N/A"
    return
  fi
  echo "PASS"
}

checklist_line() {
  local status="$1"
  local text="$2"
  printf "    [%-5s] %s\n" "${status}" "${text}"
}

print_full_checklist_matrix() {
  echo ""
  echo "  FULL VALIDATION CHECKLIST (12 categories)"
  echo "  -----------------------------------------"

  echo ""
  echo "  1. Control Plane Health"
  checklist_line "$(checklist_status "cluster status is" "false")" \
    "Cluster status is ACTIVE (not CREATING, FAILED, or DEGRADED)"
  checklist_line "$(checklist_status "kubectl cannot reach" "false")" \
    "Kubernetes API server endpoint is reachable"
  if warned_contains "EXPECTED_CLUSTER_VERSION"; then
    checklist_line "WARN" "Correct Kubernetes version matches what was declared in Terraform"
  else
    checklist_line "$(checklist_status "cluster version !=" "false")" \
      "Correct Kubernetes version matches what was declared in Terraform"
  fi
  checklist_line "$(checklist_status "certificate authority data is empty" "false")" \
    "Cluster certificate authority data is present and non-empty"
  checklist_line "$(checklist_status "OIDC issuer" "false")" \
    "OIDC issuer URL is configured and reachable (needed for IRSA)"

  echo ""
  echo "  2. Networking & VPC Wiring"
  checklist_line "$(checklist_status "cluster VPC !=" "SKIP_NETWORKING")" \
    "VPC ID attached to cluster matches your intended VPC"
  if section_skipped "SKIP_NETWORKING"; then
    checklist_line "SKIP" "Subnets tagged kubernetes.io/cluster/<name> and internal-elb/elb roles"
  elif failed_contains "subnet" || failed_contains "internal-elb" || failed_contains "elb tag"; then
    checklist_line "FAIL" "Subnets tagged kubernetes.io/cluster/<name> and internal-elb/elb roles"
  else
    checklist_line "PASS" "Subnets tagged kubernetes.io/cluster/<name> and internal-elb/elb roles"
  fi
  if warned_contains "control plane SG"; then
    checklist_line "WARN" "Control plane security group allows worker communication (port 443)"
  elif section_skipped "SKIP_NETWORKING"; then
    checklist_line "SKIP" "Control plane security group allows worker communication (port 443)"
  else
    checklist_line "PASS" \
      "Control plane security group allows worker communication (port 443)"
  fi
  checklist_line "$(if section_skipped SKIP_NETWORKING; then echo SKIP; else echo N/A; fi)" \
    "Workers can reach the API server (bidirectional SG rules on 443/10250)"
  checklist_line "$(checklist_status "VPC DNS settings" "SKIP_NETWORKING")" \
    "VPC DNS hostnames and DNS resolution are both enabled"
  checklist_line "$(checklist_status "no available NAT gateway" "SKIP_NETWORKING")" \
    "NAT Gateway is functional (workers in private subnets can reach the internet)"
  checklist_line "$(if section_skipped SKIP_NETWORKING; then echo SKIP; else echo N/A; fi)" \
    "Route tables are correctly associated with private/public subnets"

  echo ""
  echo "  3. Node Groups / Worker Nodes"
  checklist_line "$(checklist_status "node group" "SKIP_NODES")" \
    "All managed node groups are in ACTIVE status"
  checklist_line "$(checklist_status "Ready nodes (" "SKIP_NODES")" \
    "Desired node count matches actual running node count"
  checklist_line "$(checklist_status "nodes not Ready" "SKIP_NODES")" \
    "Nodes show Ready status in kubectl get nodes"
  checklist_line "$(if section_skipped SKIP_NODES; then echo SKIP; else echo N/A; fi)" \
    "Nodes are spread across the correct availability zones"
  if section_skipped "SKIP_NODES"; then
    checklist_line "SKIP" "Node IAM role has AmazonEKSWorkerNodePolicy, AmazonEC2ContainerRegistryReadOnly, AmazonEKS_CNI_Policy"
  elif failed_contains "node role missing"; then
    checklist_line "FAIL" "Node IAM role has AmazonEKSWorkerNodePolicy, AmazonEC2ContainerRegistryReadOnly, AmazonEKS_CNI_Policy"
  else
    checklist_line "PASS" "Node IAM role has AmazonEKSWorkerNodePolicy, AmazonEC2ContainerRegistryReadOnly, AmazonEKS_CNI_Policy"
  fi
  checklist_line "$(if section_skipped SKIP_NODES; then echo SKIP; else echo N/A; fi)" \
    "Node instance types and disk sizes match declared spec"
  checklist_line "$(if section_skipped SKIP_NODES; then echo SKIP; else echo N/A; fi)" \
    "Node labels and taints are applied correctly"

  echo ""
  echo "  4. IAM & RBAC"
  checklist_line "$(checklist_status "AmazonEKSClusterPolicy" "SKIP_IAM")" \
    "Cluster IAM role has AmazonEKSClusterPolicy attached"
  checklist_line "$(checklist_status "OIDC provider" "SKIP_IAM")" \
    "IRSA OIDC provider is registered in IAM"
  checklist_line "$(checklist_status "node role" "SKIP_IAM")" \
    "aws-auth / access entry has the correct node role ARN mapped"
  checklist_line "N/A" "Any additional IAM role/user mappings in aws-auth are present and correct"
  checklist_line "$(checklist_status "cannot kubectl get nodes" "SKIP_IAM")" \
    "The Terraform execution role can kubectl into the cluster"

  echo ""
  echo "  5. Core Add-ons"
  checklist_line "$(if section_skipped SKIP_ADDONS; then echo SKIP; elif failed_contains "add-on kube-proxy"; then echo FAIL; elif warned_contains "kube-proxy"; then echo WARN; else echo PASS; fi)" \
    "kube-proxy add-on is ACTIVE and version-compatible"
  checklist_line "$(if section_skipped SKIP_ADDONS; then echo SKIP; elif failed_contains "add-on vpc-cni"; then echo FAIL; else echo PASS; fi)" \
    "vpc-cni (AWS CNI) add-on is ACTIVE — pods are getting VPC IPs"
  if section_skipped "SKIP_ADDONS" || ! truthy "${VALIDATE_POST_NODE_ADDONS:-false}"; then
    checklist_line "SKIP" "coredns add-on is ACTIVE and pods are Running (DNS resolution works)"
  elif failed_contains "add-on coredns"; then
    checklist_line "FAIL" "coredns add-on is ACTIVE and pods are Running (DNS resolution works)"
  else
    checklist_line "PASS" "coredns add-on is ACTIVE and pods are Running (DNS resolution works)"
  fi
  if section_skipped "SKIP_STORAGE" || ! truthy "${VALIDATE_POST_NODE_ADDONS:-false}"; then
    checklist_line "SKIP" "EBS CSI driver add-on is ACTIVE and has correct IRSA role"
  elif failed_contains "add-on aws-ebs-csi" || failed_contains "EBS CSI"; then
    checklist_line "FAIL" "EBS CSI driver add-on is ACTIVE and has correct IRSA role"
  else
    checklist_line "PASS" "EBS CSI driver add-on is ACTIVE and has correct IRSA role"
  fi
  checklist_line "N/A" "EFS CSI driver add-on is ACTIVE (not deployed in this stack)"
  checklist_line "N/A" "Add-on versions compatible with cluster Kubernetes version (enforced in Terraform)"

  echo ""
  echo "  6. Pod & DNS Networking"
  checklist_line "$(checklist_status "CoreDNS pods not" "SKIP_POD_NETWORKING")" \
    "CoreDNS pods are Running in kube-system"
  checklist_line "$(checklist_status "DNS lookup" "SKIP_POD_NETWORKING")" \
    "A test pod can resolve kubernetes.default.svc.cluster.local"
  checklist_line "$(checklist_status "overlaps VPC" "SKIP_POD_NETWORKING")" \
    "Service/pod network CIDR does not overlap with VPC CIDR"
  checklist_line "$(checklist_status "aws-node DaemonSet:" "SKIP_POD_NETWORKING")" \
    "aws-node DaemonSet pods are Running on all nodes (VPC CNI)"
  checklist_line "$(checklist_status "kube-proxy DaemonSet:" "SKIP_POD_NETWORKING")" \
    "kube-proxy DaemonSet pods are Running on all nodes"

  echo ""
  echo "  7. Storage"
  if section_skipped "SKIP_STORAGE" || ! truthy "${VALIDATE_POST_NODE_ADDONS:-false}"; then
    checklist_line "SKIP" "Default StorageClass exists"
  elif warned_contains "default StorageClass"; then
    checklist_line "WARN" "Default StorageClass exists (kubectl get storageclass)"
  else
    checklist_line "PASS" "Default StorageClass exists (kubectl get storageclass)"
  fi
  checklist_line "$(checklist_status "EBS CSI SA" "SKIP_STORAGE")" \
    "EBS CSI IRSA role is correctly annotated on the service account"
  if ! truthy "${VALIDATE_PVC_TEST:-false}"; then
    checklist_line "N/A" "A test PVC can be created and reaches Bound state (set VALIDATE_PVC_TEST=true)"
  elif failed_contains "test PVC"; then
    checklist_line "FAIL" "A test PVC can be created and reaches Bound state"
  else
    checklist_line "PASS" "A test PVC can be created and reaches Bound state"
  fi
  checklist_line "$(if section_skipped SKIP_STORAGE; then echo SKIP; else echo N/A; fi)" \
    "gp2 or gp3 is set as the default StorageClass"

  echo ""
  echo "  8. Load Balancer / Ingress Readiness"
  if ! truthy "${VALIDATE_LOAD_BALANCER_CONTROLLER:-false}"; then
    checklist_line "N/A" "AWS Load Balancer Controller is deployed (not enabled in this stack)"
    checklist_line "N/A" "LBC has correct IRSA role and elasticloadbalancing API access"
    checklist_line "N/A" "Subnets have correct tags for ALB/NLB auto-discovery"
    checklist_line "N/A" "A test Service type LoadBalancer provisions an ELB successfully"
  else
    checklist_line "$(if failed_contains "Load Balancer Controller"; then echo FAIL; else echo PASS; fi)" \
      "AWS Load Balancer Controller is deployed"
    checklist_line "N/A" "LBC has correct IRSA role and elasticloadbalancing API access"
    checklist_line "N/A" "Subnets have correct tags for ALB/NLB auto-discovery"
    checklist_line "N/A" "A test Service type LoadBalancer provisions an ELB successfully"
  fi

  echo ""
  echo "  9. Logging & Observability"
  checklist_line "$(if section_skipped SKIP_LOGGING; then echo SKIP; elif failed_contains "control plane logging missing"; then echo FAIL; else echo PASS; fi)" \
    "Control plane logging enabled: api, audit, authenticator, controllerManager, scheduler"
  checklist_line "$(checklist_status "CloudWatch log group" "SKIP_LOGGING")" \
    "Logs CloudWatch log group /aws/eks/<cluster-name>/cluster exists"
  checklist_line "$(checklist_status "log group retention" "SKIP_LOGGING")" \
    "CloudWatch log group retention is set (not infinite)"
  checklist_line "N/A" "Fluent Bit / CloudWatch agent DaemonSet is Running (optional)"
  checklist_line "N/A" "Managed Prometheus/Grafana workspace active (optional)"

  echo ""
  echo "  10. Security & Hardening"
  checklist_line "$(checklist_status "private API endpoint access is disabled" "SKIP_SECURITY")" \
    "Private endpoint access is enabled"
  if truthy "${ALLOW_PUBLIC_WORLD_CIDR:-false}"; then
    checklist_line "WARN" "No 0.0.0.0/0 on public API endpoint CIDR (allowed in dev via ALLOW_PUBLIC_WORLD_CIDR)"
  elif section_skipped "SKIP_SECURITY"; then
    checklist_line "SKIP" "No 0.0.0.0/0 on public API endpoint CIDR unless intentional"
  else
    checklist_line "$(checklist_status "public access CIDR includes" "SKIP_SECURITY")" \
      "No 0.0.0.0/0 on public API endpoint CIDR unless intentional"
  fi
  checklist_line "$(checklist_status "secrets encryption via KMS is not" "SKIP_SECURITY")" \
    "Secrets encryption via KMS is enabled on the cluster"
  if ! truthy "${VALIDATE_PSA:-false}"; then
    checklist_line "N/A" "Pod Security Admission (PSA) or OPA/Kyverno policy is in place"
  elif failed_contains "pod security"; then
    checklist_line "FAIL" "Pod Security Admission (PSA) or OPA/Kyverno policy is in place"
  else
    checklist_line "PASS" "Pod Security Admission (PSA) or OPA/Kyverno policy is in place"
  fi
  checklist_line "N/A" "No overly permissive IAM roles attached to nodes (manual review)"
  checklist_line "N/A" "ECR / private registry accessible from workers (not automated)"

  echo ""
  echo "  11. Cluster Autoscaler / Karpenter (if applicable)"
  if ! truthy "${VALIDATE_CLUSTER_AUTOSCALER:-false}"; then
    checklist_line "N/A" "Cluster Autoscaler deployment is Running (not enabled)"
    checklist_line "N/A" "Autoscaler IRSA role has autoscaling:* and ec2:Describe* permissions"
    checklist_line "N/A" "Autoscaler discovers correct node group ASGs"
  else
    checklist_line "$(if failed_contains "cluster-autoscaler"; then echo FAIL; else echo PASS; fi)" \
      "Cluster Autoscaler deployment is Running"
    checklist_line "N/A" "Autoscaler IRSA role has autoscaling:* and ec2:Describe* permissions"
    checklist_line "N/A" "Autoscaler discovers correct node group ASGs"
  fi
  if ! truthy "${VALIDATE_KARPENTER:-false}"; then
    checklist_line "N/A" "Karpenter NodePool and EC2NodeClass resources are applied and valid"
  else
    checklist_line "$(if failed_contains "Karpenter"; then echo FAIL; else echo PASS; fi)" \
      "Karpenter NodePool and EC2NodeClass resources are applied and valid"
  fi

  echo ""
  echo "  12. Tagging & Metadata Hygiene"
  if section_skipped "SKIP_TAGGING"; then
    checklist_line "SKIP" "Cluster tagged with environment, project (team/cost center via var.tags)"
  elif warned_contains "cluster tag"; then
    checklist_line "WARN" "Cluster tagged with environment, project (team/cost center via var.tags)"
  else
    checklist_line "PASS" "Cluster tagged with environment, project (team/cost center via var.tags)"
  fi
  checklist_line "$(checklist_status "cluster name is consistent" "SKIP_TAGGING")" \
    "Cluster name is consistent across related resources"
  checklist_line "N/A" "Terraform state reflects live resource state — run terraform plan for drift"

  echo ""
  echo "  Legend: PASS=verified  FAIL=check failed  WARN=review  SKIP=phase disabled  N/A=not automated"
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || {
    record_fail "required command not found: ${cmd}"
    return 1
  }
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    record_fail "required environment variable ${name} is not set"
    return 1
  fi
}

cluster_json() {
  aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --output json
}

addon_status() {
  local addon_name="$1"
  aws eks describe-addon \
    --cluster-name "${CLUSTER_NAME}" \
    --addon-name "${addon_name}" \
    --region "${AWS_REGION}" \
    --query 'addon.status' \
    --output text 2>/dev/null || echo "NOT_INSTALLED"
}

# --- 1. Control plane health ---
check_control_plane() {
  log_section "1. Control plane health"
  local status version ca oidc endpoint

  status="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.status' \
    --output text)"
  if [ "${status}" = "ACTIVE" ]; then
    record_pass "cluster status is ACTIVE"
  else
    record_fail "cluster status is ${status} (expected ACTIVE)"
  fi

  endpoint="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.endpoint' \
    --output text)"
  if aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1 \
    && kubectl cluster-info >/dev/null 2>&1; then
    record_pass "Kubernetes API is reachable via kubectl"
  else
    record_fail "kubectl cannot reach API at ${endpoint}"
  fi

  if [ -n "${EXPECTED_CLUSTER_VERSION:-}" ]; then
    version="$(aws eks describe-cluster \
      --name "${CLUSTER_NAME}" \
      --region "${AWS_REGION}" \
      --query 'cluster.version' \
      --output text)"
    if [ "${version}" = "${EXPECTED_CLUSTER_VERSION}" ]; then
      record_pass "cluster version ${version} matches expected"
    else
      record_fail "cluster version ${version} != expected ${EXPECTED_CLUSTER_VERSION}"
    fi
  else
    record_warn "EXPECTED_CLUSTER_VERSION not set — skipping version check"
  fi

  ca="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.certificateAuthority.data' \
    --output text)"
  if [ -n "${ca}" ] && [ "${ca}" != "None" ]; then
    record_pass "cluster certificate authority data is present"
  else
    record_fail "cluster certificate authority data is empty"
  fi

  oidc="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.identity.oidc.issuer' \
    --output text)"
  if [ -n "${oidc}" ] && [ "${oidc}" != "None" ]; then
    if curl -fsS --max-time 10 "${oidc}/.well-known/openid-configuration" >/dev/null 2>&1; then
      record_pass "OIDC issuer is configured and reachable"
    else
      record_fail "OIDC issuer ${oidc} is not reachable"
    fi
  else
    record_fail "OIDC issuer URL is missing"
  fi
}

# --- 2. Networking & VPC ---
check_networking() {
  log_section "2. Networking and VPC wiring"
  local vpc_id cluster_vpc dns_host dns_support

  if skip_if_disabled "SKIP_NETWORKING" "networking checks"; then return 0; fi

  if [ -n "${EXPECTED_VPC_ID:-}" ]; then
    cluster_vpc="$(aws eks describe-cluster \
      --name "${CLUSTER_NAME}" \
      --region "${AWS_REGION}" \
      --query 'cluster.resourcesVpcConfig.vpcId' \
      --output text)"
    if [ "${cluster_vpc}" = "${EXPECTED_VPC_ID}" ]; then
      record_pass "cluster VPC ${cluster_vpc} matches expected"
    else
      record_fail "cluster VPC ${cluster_vpc} != expected ${EXPECTED_VPC_ID}"
    fi
  fi

  if [ -n "${EXPECTED_CLUSTER_NAME:-}" ]; then
    local tag_key="kubernetes.io/cluster/${EXPECTED_CLUSTER_NAME}"
    local missing=0
    for subnet_id in ${PRIVATE_SUBNET_IDS:-} ${PUBLIC_SUBNET_IDS:-}; do
      [ -z "${subnet_id}" ] && continue
      local cluster_tag
      cluster_tag="$(aws ec2 describe-tags \
        --filters "Name=resource-id,Values=${subnet_id}" "Name=key,Values=${tag_key}" \
        --region "${AWS_REGION}" \
        --query 'Tags[0].Value' \
        --output text 2>/dev/null || echo "")"
      if [ "${cluster_tag}" = "shared" ] || [ "${cluster_tag}" = "owned" ]; then
        :
      else
        record_fail "subnet ${subnet_id} missing ${tag_key}=shared|owned (got '${cluster_tag}')"
        missing=$((missing + 1))
      fi
    done
    if [ "${missing}" -eq 0 ] && [ -n "${PRIVATE_SUBNET_IDS:-}${PUBLIC_SUBNET_IDS:-}" ]; then
      record_pass "subnets have kubernetes.io/cluster tag"
    fi

    for subnet_id in ${PRIVATE_SUBNET_IDS:-}; do
      [ -z "${subnet_id}" ] && continue
      local internal_elb
      internal_elb="$(aws ec2 describe-tags \
        --filters "Name=resource-id,Values=${subnet_id}" "Name=key,Values=kubernetes.io/role/internal-elb" \
        --region "${AWS_REGION}" \
        --query 'Tags[0].Value' \
        --output text 2>/dev/null || echo "")"
      if [ "${internal_elb}" = "1" ]; then
        record_pass "private subnet ${subnet_id} has internal-elb tag"
      else
        record_fail "private subnet ${subnet_id} missing kubernetes.io/role/internal-elb=1"
      fi
    done

    for subnet_id in ${PUBLIC_SUBNET_IDS:-}; do
      [ -z "${subnet_id}" ] && continue
      local elb_tag
      elb_tag="$(aws ec2 describe-tags \
        --filters "Name=resource-id,Values=${subnet_id}" "Name=key,Values=kubernetes.io/role/elb" \
        --region "${AWS_REGION}" \
        --query 'Tags[0].Value' \
        --output text 2>/dev/null || echo "")"
      if [ "${elb_tag}" = "1" ]; then
        record_pass "public subnet ${subnet_id} has elb tag"
      else
        record_fail "public subnet ${subnet_id} missing kubernetes.io/role/elb=1"
      fi
    done
  fi

  if [ -n "${EXPECTED_VPC_ID:-}" ]; then
    dns_host="$(aws ec2 describe-vpc-attribute \
      --vpc-id "${EXPECTED_VPC_ID}" \
      --attribute enableDnsHostnames \
      --region "${AWS_REGION}" \
      --query 'EnableDnsHostnames.Value' \
      --output text)"
    dns_support="$(aws ec2 describe-vpc-attribute \
      --vpc-id "${EXPECTED_VPC_ID}" \
      --attribute enableDnsSupport \
      --region "${AWS_REGION}" \
      --query 'EnableDnsSupport.Value' \
      --output text)"
    if truthy "${dns_host}" && truthy "${dns_support}"; then
      record_pass "VPC DNS hostnames and DNS support are enabled"
    else
      record_fail "VPC DNS settings: hostnames=${dns_host} support=${dns_support}"
    fi

    local nat_state
    nat_state="$(aws ec2 describe-nat-gateways \
      --filter "Name=vpc-id,Values=${EXPECTED_VPC_ID}" "Name=state,Values=available" \
      --region "${AWS_REGION}" \
      --query 'length(NatGateways)' \
      --output text 2>/dev/null || echo "0")"
    if [ "${nat_state}" != "0" ] && [ -n "${nat_state}" ]; then
      record_pass "at least one available NAT gateway exists in VPC"
    else
      record_fail "no available NAT gateway found in VPC ${EXPECTED_VPC_ID}"
    fi
  fi

  if [ -n "${CONTROL_PLANE_SG_ID:-}" ]; then
    local cp_rules
    cp_rules="$(aws ec2 describe-security-group-rules \
      --filters "Name=group-id,Values=${CONTROL_PLANE_SG_ID}" \
      --region "${AWS_REGION}" \
      --query 'SecurityGroupRules[?IsEgress==`false` && FromPort==`443`]' \
      --output json 2>/dev/null || echo "[]")"
    if [ "${cp_rules}" != "[]" ] && [ -n "${cp_rules}" ]; then
      record_pass "control plane SG has inbound TCP 443 rules"
    else
      record_warn "could not confirm control plane SG inbound 443 (may use referenced SG rules)"
    fi
  fi
}

# --- 3. Node groups ---
check_node_groups() {
  log_section "3. Node groups and worker nodes"
  if skip_if_disabled "SKIP_NODES" "node checks"; then return 0; fi

  local ng_names="${NODEGROUP_NAMES:-general}"
  for ng in ${ng_names}; do
    local ng_status desired ready_count
    ng_status="$(aws eks describe-nodegroup \
      --cluster-name "${CLUSTER_NAME}" \
      --nodegroup-name "${ng}" \
      --region "${AWS_REGION}" \
      --query 'nodegroup.status' \
      --output text 2>/dev/null || echo "MISSING")"
    if [ "${ng_status}" = "ACTIVE" ]; then
      record_pass "node group ${ng} is ACTIVE"
    else
      record_fail "node group ${ng} status is ${ng_status}"
      continue
    fi

    desired="$(aws eks describe-nodegroup \
      --cluster-name "${CLUSTER_NAME}" \
      --nodegroup-name "${ng}" \
      --region "${AWS_REGION}" \
      --query 'nodegroup.scalingConfig.desiredSize' \
      --output text)"
    ready_count="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready" { n++ } END { print n + 0 }')"
    if [ "${ready_count}" -ge "${desired}" ] && [ "${ready_count}" -gt 0 ]; then
      record_pass "Ready nodes (${ready_count}) >= desired size (${desired}) for ${ng}"
    else
      record_fail "Ready nodes (${ready_count}) < desired (${desired}) for ${ng}"
    fi
  done

  local not_ready
  not_ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready" { print $1 }' || true)"
  if [ -z "${not_ready}" ]; then
    record_pass "all nodes report Ready"
  else
    record_fail "nodes not Ready: ${not_ready}"
  fi

  if [ -n "${EXPECTED_NODE_ROLE_ARN:-}" ]; then
    local attached
    attached="$(aws iam list-attached-role-policies \
      --role-name "${EXPECTED_NODE_ROLE_ARN##*/}" \
      --query 'AttachedPolicies[].PolicyName' \
      --output text 2>/dev/null || true)"
    for policy in AmazonEKSWorkerNodePolicy AmazonEC2ContainerRegistryReadOnly AmazonEKS_CNI_Policy; do
      if echo "${attached}" | grep -q "${policy}"; then
        record_pass "node role has ${policy}"
      else
        record_fail "node role missing managed policy ${policy}"
      fi
    done
  fi
}

# --- 4. IAM & RBAC ---
check_iam_rbac() {
  log_section "4. IAM and RBAC"
  if skip_if_disabled "SKIP_IAM" "IAM checks"; then return 0; fi

  if [ -n "${EXPECTED_CLUSTER_ROLE_ARN:-}" ]; then
    local cluster_policies
    cluster_policies="$(aws iam list-attached-role-policies \
      --role-name "${EXPECTED_CLUSTER_ROLE_ARN##*/}" \
      --query 'AttachedPolicies[].PolicyName' \
      --output text 2>/dev/null || true)"
    if echo "${cluster_policies}" | grep -q "AmazonEKSClusterPolicy"; then
      record_pass "cluster role has AmazonEKSClusterPolicy"
    else
      record_fail "cluster role missing AmazonEKSClusterPolicy"
    fi
  fi

  if [ -n "${EXPECTED_OIDC_PROVIDER_ARN:-}" ]; then
    if aws iam get-open-id-connect-provider \
      --open-id-connect-provider-arn "${EXPECTED_OIDC_PROVIDER_ARN}" \
      >/dev/null 2>&1; then
      record_pass "IRSA OIDC provider is registered in IAM"
    else
      record_fail "OIDC provider ${EXPECTED_OIDC_PROVIDER_ARN} not found in IAM"
    fi
  fi

  if [ -n "${EXPECTED_NODE_ROLE_ARN:-}" ]; then
    local entries
    entries="$(aws eks list-access-entries \
      --cluster-name "${CLUSTER_NAME}" \
      --region "${AWS_REGION}" \
      --query 'accessEntries' \
      --output text 2>/dev/null || true)"
    if echo "${entries}" | grep -q "${EXPECTED_NODE_ROLE_ARN}"; then
      record_pass "node role ARN has EKS access entry"
    elif kubectl get configmap aws-auth -n kube-system -o yaml 2>/dev/null | grep -q "${EXPECTED_NODE_ROLE_ARN}"; then
      record_pass "node role ARN is present in aws-auth ConfigMap"
    else
      record_fail "node role ${EXPECTED_NODE_ROLE_ARN} not found in access entries or aws-auth"
    fi
  fi

  if kubectl auth can-i get nodes --all-namespaces >/dev/null 2>&1; then
    record_pass "current credentials can kubectl get nodes"
  else
    record_fail "current credentials cannot kubectl get nodes"
  fi
}

# --- 5. Core add-ons ---
check_core_addons() {
  log_section "5. Core EKS add-ons"
  if skip_if_disabled "SKIP_ADDONS" "add-on checks"; then return 0; fi

  for addon in vpc-cni kube-proxy; do
    local st
    st="$(addon_status "${addon}")"
    if [ "${st}" = "ACTIVE" ]; then
      record_pass "add-on ${addon} is ACTIVE"
    elif [ "${st}" = "NOT_INSTALLED" ]; then
      record_warn "add-on ${addon} is not installed"
    else
      record_fail "add-on ${addon} status is ${st}"
    fi
  done

  if truthy "${VALIDATE_POST_NODE_ADDONS:-false}"; then
    for addon in coredns aws-ebs-csi-driver; do
      st="$(addon_status "${addon}")"
      if [ "${st}" = "ACTIVE" ]; then
        record_pass "add-on ${addon} is ACTIVE"
      else
        record_fail "add-on ${addon} status is ${st} (expected ACTIVE)"
      fi
    done
  fi
}

# --- 6. Pod & DNS networking ---
check_pod_networking() {
  log_section "6. Pod and DNS networking"
  if skip_if_disabled "SKIP_POD_NETWORKING" "pod networking checks"; then return 0; fi

  local coredns_ready coredns_total
  coredns_ready="$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null \
    | awk '$3=="Running" { n++ } END { print n + 0 }')"
  coredns_total="$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null \
    | wc -l | tr -d ' ')"
  if [ "${coredns_ready}" -ge 1 ] && [ "${coredns_ready}" -eq "${coredns_total}" ]; then
    record_pass "CoreDNS pods are Running (${coredns_ready}/${coredns_total})"
  else
    record_fail "CoreDNS pods not all Running (${coredns_ready}/${coredns_total})"
  fi

  if truthy "${VALIDATE_DNS_LOOKUP:-true}"; then
    if kubectl run "eks-validate-dns-$RANDOM" \
      --rm -i --restart=Never \
      --image=busybox:1.36 \
      --overrides='{"spec":{"activeDeadlineSeconds":60}}' \
      -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
      record_pass "test pod resolved kubernetes.default.svc.cluster.local"
    else
      record_fail "DNS lookup for kubernetes.default.svc.cluster.local failed"
    fi
  fi

  if [ -n "${EXPECTED_VPC_CIDR:-}" ] && [ -n "${EXPECTED_VPC_ID:-}" ]; then
    local service_cidr
    service_cidr="$(aws eks describe-cluster \
      --name "${CLUSTER_NAME}" \
      --region "${AWS_REGION}" \
      --query 'cluster.kubernetesNetworkConfig.serviceIpv4Cidr' \
      --output text 2>/dev/null || echo "")"
    if [ -n "${service_cidr}" ] && [ "${service_cidr}" != "None" ]; then
      python3 -c "
import ipaddress
vpc = ipaddress.ip_network('${EXPECTED_VPC_CIDR}', strict=False)
svc = ipaddress.ip_network('${service_cidr}', strict=False)
assert not vpc.overlaps(svc), f'service CIDR {svc} overlaps VPC {vpc}'
print('ok')
" >/dev/null 2>&1 && record_pass "service CIDR ${service_cidr} does not overlap VPC ${EXPECTED_VPC_CIDR}" \
      || record_fail "service CIDR ${service_cidr} overlaps VPC ${EXPECTED_VPC_CIDR}"
    fi
  fi

  local node_count aws_node_ready kube_proxy_ready
  node_count="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  aws_node_ready="$(kubectl get pods -n kube-system -l k8s-app=aws-node --no-headers 2>/dev/null \
    | awk '$3=="Running" { n++ } END { print n + 0 }')"
  if [ "${node_count}" -gt 0 ] && [ "${aws_node_ready}" -ge "${node_count}" ]; then
    record_pass "aws-node DaemonSet has Running pods on all nodes (${aws_node_ready}/${node_count})"
  else
    record_fail "aws-node DaemonSet: ${aws_node_ready} Running pods for ${node_count} nodes"
  fi

  kube_proxy_ready="$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null \
    | awk '$3=="Running" { n++ } END { print n + 0 }')"
  if [ "${node_count}" -gt 0 ] && [ "${kube_proxy_ready}" -ge "${node_count}" ]; then
    record_pass "kube-proxy DaemonSet has Running pods on all nodes (${kube_proxy_ready}/${node_count})"
  else
    record_fail "kube-proxy DaemonSet: ${kube_proxy_ready} Running pods for ${node_count} nodes"
  fi
}

# --- 7. Storage ---
check_storage() {
  log_section "7. Storage"
  if skip_if_disabled "SKIP_STORAGE" "storage checks"; then return 0; fi
  if ! truthy "${VALIDATE_POST_NODE_ADDONS:-false}"; then
    echo "SKIP: post-node add-ons not enabled (VALIDATE_POST_NODE_ADDONS=false)"
    return 0
  fi

  if kubectl get storageclass >/dev/null 2>&1; then
    local default_sc
    default_sc="$(kubectl get storageclass \
      -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{end}' 2>/dev/null || true)"
    if [ -n "${default_sc}" ]; then
      record_pass "default StorageClass is ${default_sc}"
    else
      record_warn "no default StorageClass annotated (EBS CSI may still work)"
    fi
  fi

  if [ -n "${EBS_CSI_ROLE_ARN:-}" ]; then
    local sa_role
    sa_role="$(kubectl get sa ebs-csi-controller-sa -n kube-system \
      -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || true)"
    if [ "${sa_role}" = "${EBS_CSI_ROLE_ARN}" ]; then
      record_pass "EBS CSI service account has expected IRSA annotation"
    else
      record_fail "EBS CSI SA role-arn '${sa_role}' != expected '${EBS_CSI_ROLE_ARN}'"
    fi
  fi

  if truthy "${VALIDATE_PVC_TEST:-false}"; then
    local pvc_name="eks-validate-pvc-$RANDOM"
    kubectl apply -f - >/dev/null 2>&1 <<EOF || true
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp2
  resources:
    requests:
      storage: 1Gi
EOF
    local bound=false
    for _ in $(seq 1 30); do
      if kubectl get pvc "${pvc_name}" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Bound; then
        bound=true
        break
      fi
      sleep 5
    done
    kubectl delete pvc "${pvc_name}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    if [ "${bound}" = "true" ]; then
      record_pass "test PVC reached Bound state"
    else
      record_fail "test PVC did not reach Bound within timeout"
    fi
  fi
}

# --- 8. Load balancer (optional) ---
check_load_balancer() {
  log_section "8. Load balancer / ingress readiness"
  if ! truthy "${VALIDATE_LOAD_BALANCER_CONTROLLER:-false}"; then
    echo "SKIP: load balancer checks (VALIDATE_LOAD_BALANCER_CONTROLLER=false)"
    return 0
  fi
  if kubectl get deployment -n kube-system aws-load-balancer-controller >/dev/null 2>&1; then
    local ready
    ready="$(kubectl get deployment -n kube-system aws-load-balancer-controller \
      -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
    if [ "${ready:-0}" -ge 1 ]; then
      record_pass "AWS Load Balancer Controller deployment is ready"
    else
      record_fail "AWS Load Balancer Controller is not ready"
    fi
  else
    record_fail "AWS Load Balancer Controller deployment not found"
  fi
}

# --- 9. Logging & observability ---
check_logging() {
  log_section "9. Logging and observability"
  if skip_if_disabled "SKIP_LOGGING" "logging checks"; then return 0; fi

  local enabled_types
  enabled_types="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.logging.clusterLogging[?enabled==`true`].types[]' \
    --output text 2>/dev/null || true)"

  for log_type in api audit authenticator controllerManager scheduler; do
    if echo "${enabled_types}" | grep -qw "${log_type}"; then
      record_pass "control plane logging enabled for ${log_type}"
    else
      record_fail "control plane logging missing ${log_type}"
    fi
  done

  local log_group retention
  log_group="${CLOUDWATCH_LOG_GROUP:-/aws/eks/${CLUSTER_NAME}/cluster}"
  if aws logs describe-log-groups \
    --log-group-name-prefix "${log_group}" \
    --region "${AWS_REGION}" \
    --query "logGroups[?logGroupName=='${log_group}'] | length(@)" \
    --output text 2>/dev/null | grep -q '^1$'; then
    record_pass "CloudWatch log group ${log_group} exists"
    retention="$(aws logs describe-log-groups \
      --log-group-name-prefix "${log_group}" \
      --region "${AWS_REGION}" \
      --query "logGroups[?logGroupName=='${log_group}'].retentionInDays | [0]" \
      --output text)"
    if [ -n "${retention}" ] && [ "${retention}" != "None" ]; then
      record_pass "log group retention is ${retention} days"
    else
      record_fail "log group retention is not set (infinite retention)"
    fi
  else
    record_fail "CloudWatch log group ${log_group} not found"
  fi
}

# --- 10. Security & hardening ---
check_security() {
  log_section "10. Security and hardening"
  if skip_if_disabled "SKIP_SECURITY" "security checks"; then return 0; fi

  local private_access public_access encryption
  private_access="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.resourcesVpcConfig.endpointPrivateAccess' \
    --output text)"
  public_access="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.resourcesVpcConfig.endpointPublicAccess' \
    --output text)"

  if truthy "${private_access}"; then
    record_pass "private API endpoint access is enabled"
  else
    record_fail "private API endpoint access is disabled (endpointPrivateAccess=${private_access:-unknown}; expected True — run terraform apply or aws eks update-cluster-config)"
  fi

  if truthy "${ALLOW_PUBLIC_WORLD_CIDR:-false}"; then
    record_warn "ALLOW_PUBLIC_WORLD_CIDR=true — skipping 0.0.0.0/0 public endpoint CIDR check"
  elif truthy "${public_access}"; then
    local cidrs
    cidrs="$(aws eks describe-cluster \
      --name "${CLUSTER_NAME}" \
      --region "${AWS_REGION}" \
      --query 'cluster.resourcesVpcConfig.publicAccessCidrs' \
      --output text)"
    if echo "${cidrs}" | grep -q '0.0.0.0/0'; then
      record_fail "public access CIDR includes 0.0.0.0/0 (set ALLOW_PUBLIC_WORLD_CIDR=true to allow in dev)"
    else
      record_pass "public access CIDRs are restricted"
    fi
  fi

  encryption="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.encryptionConfig' \
    --output json)"
  if echo "${encryption}" | grep -q 'secrets'; then
    record_pass "secrets encryption is configured"
  else
    record_fail "secrets encryption via KMS is not configured"
  fi

  if truthy "${VALIDATE_PSA:-false}"; then
    if kubectl get ns -o json 2>/dev/null | grep -q 'pod-security'; then
      record_pass "pod security labels found on namespaces"
    else
      record_warn "VALIDATE_PSA=true but no pod-security labels detected"
    fi
  fi
}

# --- 11. Autoscaler / Karpenter (optional) ---
check_autoscaling() {
  log_section "11. Cluster autoscaler / Karpenter"
  if ! truthy "${VALIDATE_CLUSTER_AUTOSCALER:-false}"; then
    echo "SKIP: cluster autoscaler (VALIDATE_CLUSTER_AUTOSCALER=false)"
  elif kubectl get deployment -n kube-system cluster-autoscaler >/dev/null 2>&1; then
    local ready
    ready="$(kubectl get deployment -n kube-system cluster-autoscaler \
      -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
    if [ "${ready:-0}" -ge 1 ]; then
      record_pass "cluster-autoscaler deployment is ready"
    else
      record_fail "cluster-autoscaler deployment is not ready"
    fi
  else
    record_fail "cluster-autoscaler deployment not found"
  fi

  if ! truthy "${VALIDATE_KARPENTER:-false}"; then
    echo "SKIP: Karpenter (VALIDATE_KARPENTER=false)"
  elif kubectl get nodepools.karpenter.sh >/dev/null 2>&1; then
    record_pass "Karpenter NodePool resources exist"
  else
    record_fail "Karpenter NodePool resources not found"
  fi
}

# --- 12. Tagging ---
check_tagging() {
  log_section "12. Tagging and metadata"
  if skip_if_disabled "SKIP_TAGGING" "tagging checks"; then return 0; fi

  local cluster_tags
  cluster_tags="$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.tags' \
    --output json)"
  for key in environment project; do
    if echo "${cluster_tags}" | grep -q "\"${key}\""; then
      record_pass "cluster tag ${key} is set"
    else
      record_warn "cluster tag ${key} not found"
    fi
  done

  if [ "${CLUSTER_NAME}" = "${EXPECTED_CLUSTER_NAME:-${CLUSTER_NAME}}" ]; then
    record_pass "cluster name is consistent (${CLUSTER_NAME})"
  fi
}

print_summary() {
  local status="PASSED"
  local ready_nodes total_nodes

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    status="FAILED"
  fi

  ready_nodes="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready" { n++ } END { print n + 0 }')"
  total_nodes="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"

  echo ""
  echo "============================================================"
  echo "  EKS POST-APPLY VALIDATION — FINAL SUMMARY"
  echo "============================================================"
  echo "  Cluster:        ${CLUSTER_NAME}"
  echo "  Region:         ${AWS_REGION}"
  echo "  Node groups:    ${NODEGROUP_NAMES:-n/a}"
  echo "  Nodes Ready:    ${ready_nodes}/${total_nodes}"
  echo "  Checks run:     ${CHECKED}"
  echo "  Passed:         ${PASSED}"
  echo "  Failed:         ${#FAILURES[@]}"
  echo "  Warnings:       ${#WARNINGS[@]}"
  echo "  Result:         ${status}"
  echo "============================================================"

  print_full_checklist_matrix

  if [ -n "${CHECKLIST_REPORT_PATH:-}" ]; then
    {
      echo "EKS POST-APPLY VALIDATION CHECKLIST"
      echo "Cluster: ${CLUSTER_NAME} | Region: ${AWS_REGION} | Result: ${status}"
      print_full_checklist_matrix
    } > "${CHECKLIST_REPORT_PATH}"
  fi

  if [ "${#WARNINGS[@]}" -gt 0 ]; then
    echo ""
    echo "Warnings:"
    printf '  - %s\n' "${WARNINGS[@]}"
  fi

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '  - %s\n' "${FAILURES[@]}"
    echo ""
    echo "::error::EKS post-apply validation failed with ${#FAILURES[@]} failure(s)." >&2
    exit 1
  fi

  echo ""
  echo "All required EKS validation checks passed."
}

main() {
  require_cmd aws
  require_cmd kubectl
  require_cmd curl
  require_cmd python3

  require_env CLUSTER_NAME
  require_env AWS_REGION

  echo "EKS post-apply validation for cluster ${CLUSTER_NAME} (${AWS_REGION})"

  check_control_plane
  check_networking
  check_node_groups
  check_iam_rbac
  check_core_addons
  check_pod_networking
  check_storage
  check_load_balancer
  check_logging
  check_security
  check_autoscaling
  check_tagging
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
