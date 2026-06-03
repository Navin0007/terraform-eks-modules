# EKS post-apply validation

Terraform provisions infrastructure; this suite confirms the **live** cluster matches intent using `aws` CLI and `kubectl`. Failures block CI apply and surface as `null_resource` errors on `terraform apply`.

## Implementation map

| Approach | Location | When it runs |
|----------|----------|--------------|
| `null_resource` + `local-exec` | `modules/eks-validation` | End of `terraform apply` when wired in `environments/dev/eks_validation.tf` |
| CI/CD script | `.github/scripts/terraform-common.sh` → `run_eks_post_apply_validation` | **Every** successful `environments/dev` apply in GitHub Actions; prints validation summary + `DEV STACK POST-APPLY — FINAL SUMMARY` at end of logs |
| `check` blocks | `environments/dev/eks_phases.tf` | **Plan** time — stage ordering only |
| `postcondition` on data source | `modules/addons/main.tf` | Cluster must be `ACTIVE` before post-node add-ons |

Script: [`modules/eks-validation/scripts/validate-eks-cluster.sh`](../modules/eks-validation/scripts/validate-eks-cluster.sh)

## Checklist by category

### 1. Control plane health

| Check | Script |
|-------|--------|
| Cluster status `ACTIVE` | `aws eks describe-cluster` |
| API reachable | `kubectl cluster-info` |
| Version matches Terraform | `EXPECTED_CLUSTER_VERSION` |
| CA data present | `certificateAuthority.data` |
| OIDC issuer reachable | curl `/.well-known/openid-configuration` |

### 2. Networking & VPC wiring

| Check | Script |
|-------|--------|
| VPC ID matches | `EXPECTED_VPC_ID` |
| Subnet tags `kubernetes.io/cluster/<name>` | `shared` or `owned` (this repo uses **shared**) |
| `internal-elb` / `elb` tags | private/public subnet tag checks |
| VPC DNS hostnames + support | `describe-vpc-attribute` |
| NAT gateway available | `describe-nat-gateways` |
| Control plane SG 443 | security group rules (warn if referenced-SG only) |

### 3. Node groups / worker nodes

| Check | Script |
|-------|--------|
| Node group `ACTIVE` | per `NODEGROUP_NAMES` |
| Ready count ≥ desired | kubectl + `describe-nodegroup` |
| All nodes `Ready` | `kubectl get nodes` |
| Node IAM policies | `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEKS_CNI_Policy` |

*Not automated here:* AZ spread per node, instance type/disk/labels/taints (add assertions if you need strict spec matching).

### 4. IAM & RBAC

| Check | Script |
|-------|--------|
| Cluster role `AmazonEKSClusterPolicy` | IAM list attached policies |
| OIDC provider in IAM | `get-open-id-connect-provider` |
| Node role in access entries or `aws-auth` | API mode + ConfigMap fallback |
| Caller can `kubectl get nodes` | `kubectl auth can-i` |

### 5. Core add-ons

| Check | Script |
|-------|--------|
| `vpc-cni`, `kube-proxy` `ACTIVE` | `aws eks describe-addon` |
| `coredns`, `aws-ebs-csi-driver` | when `VALIDATE_POST_NODE_ADDONS=true` |

*Version compatibility:* enforce in Terraform (`aws_eks_addon.addon_version`); extend script with `EXPECTED_*_ADDON_VERSION` if needed.

### 6. Pod & DNS networking

| Check | Script |
|-------|--------|
| CoreDNS pods Running | label `k8s-app=kube-dns` |
| DNS lookup test pod | `nslookup kubernetes.default.svc.cluster.local` |
| Service CIDR vs VPC CIDR | no overlap (VPC CNI) |
| `aws-node`, `kube-proxy` DaemonSets | Running count ≥ node count |

### 7. Storage

| Check | Script |
|-------|--------|
| Default StorageClass | annotation on StorageClass |
| EBS CSI IRSA annotation | SA `ebs-csi-controller-sa` |
| Test PVC Bound | optional `VALIDATE_PVC_TEST=true` |

### 8. Load balancer / ingress

| Check | Script |
|-------|--------|
| AWS LBC deployed | `VALIDATE_LOAD_BALANCER_CONTROLLER=true` (off by default) |
| Test `LoadBalancer` Service | not included — add in your environment if needed |

### 9. Logging & observability

| Check | Script |
|-------|--------|
| Log types api, audit, authenticator, controllerManager, scheduler | `describe-cluster` logging |
| CloudWatch log group exists | `/aws/eks/<cluster>/cluster` |
| Retention set | not infinite |

*Fluent Bit / AMP:* optional flags not enabled in this repo.

### 10. Security & hardening

| Check | Script |
|-------|--------|
| Private endpoint enabled | `endpointPrivateAccess` |
| No `0.0.0.0/0` on public endpoint | skipped when `ALLOW_PUBLIC_WORLD_CIDR=true` (dev) |
| Secrets KMS encryption | `encryptionConfig` includes `secrets` |
| PSA / Kyverno | `VALIDATE_PSA=true` (off by default) |

### 11. Cluster Autoscaler / Karpenter

| Check | Script |
|-------|--------|
| Autoscaler deployment | `VALIDATE_CLUSTER_AUTOSCALER=true` |
| Karpenter NodePools | `VALIDATE_KARPENTER=true` |

### 12. Tagging & metadata

| Check | Script |
|-------|--------|
| `environment`, `project` tags on cluster | warn if missing |
| Cluster name consistency | `EXPECTED_CLUSTER_NAME` |

*Drift:* use `terraform plan` in CI; not duplicated in this script.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `CLUSTER_NAME`, `AWS_REGION` | Required |
| `EXPECTED_*` | Values from Terraform outputs |
| `VALIDATE_POST_NODE_ADDONS` | CoreDNS, EBS CSI, storage section |
| `VALIDATE_PVC_TEST` | Create/delete 1Gi PVC |
| `ALLOW_PUBLIC_WORLD_CIDR` | Allow dev `0.0.0.0/0` public API CIDR |
| `SKIP_*` | Skip category (`SKIP_NETWORKING=true`, etc.) |
| `VALIDATE_LOAD_BALANCER_CONTROLLER` | Section 8 |
| `VALIDATE_CLUSTER_AUTOSCALER`, `VALIDATE_KARPENTER` | Section 11 |

## Wiring in Terraform

```hcl
module "eks_validation" {
  source = "../../modules/eks-validation"

  cluster_name = module.eks[0].cluster_name
  region       = var.region
  # ... pass outputs from vpc, iam, eks, addons
  validate_post_node_addons = true
  allow_public_world_cidr   = true # dev only
}
```

Set `enabled = false` on the module to disable `local-exec` while keeping the script for CI-only runs.

## Manual run

```bash
export CLUSTER_NAME="my-project-dev-eks"
export AWS_REGION="us-east-1"
export EXPECTED_VPC_ID="vpc-..."
# ... other EXPECTED_* vars from terraform output
bash modules/eks-validation/scripts/validate-eks-cluster.sh
```

## Recommended extensions

- **Terratest** — Go integration tests calling the same script or shared check library.
- **`check` blocks** — assert `aws_eks_cluster.main.status == "ACTIVE"` where the attribute is known at plan time (post-apply still needs kubectl).
- **Load balancer smoke test** — deploy a throwaway `Service type=LoadBalancer` behind `VALIDATE_LB_SMOKE_TEST=true`.
