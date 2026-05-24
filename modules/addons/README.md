# EKS Add-ons Module

Installs and manages core Amazon EKS managed add-ons on an existing cluster. Apply this module last in the stack: the EKS cluster must be fully active and IRSA roles from the IAM module must exist before add-ons are created.

## Managed add-ons

| Add-on | IRSA required | Notes |
|--------|:-------------:|-------|
| `coredns` | No | Cluster DNS; does not call AWS APIs |
| `vpc-cni` | Yes | Assigns pod IP addresses from the VPC; requires `vpc_cni_role_arn` |
| `kube-proxy` | No | Network proxy on each node; does not call AWS APIs |
| `aws-ebs-csi-driver` | Yes | Provisions EBS volumes for persistent volumes; requires `ebs_csi_role_arn` |

Without IRSA on `vpc-cni`, the CNI cannot assign pod IPs from the VPC. Without IRSA on `aws-ebs-csi-driver`, persistent volume creation fails silently at runtime.

## Pinning add-on versions

Pass `addon_versions` to pin specific versions. Keys must match EKS add-on names. Omit a key or leave the map empty (`{}`) to let AWS install the default version for the cluster Kubernetes version.

```hcl
module "addons" {
  source = "../../modules/addons"

  project_name   = var.project_name
  environment    = var.environment
  cluster_name   = module.eks.cluster_name
  cluster_id     = module.eks.cluster_id
  cluster_version = module.eks.cluster_version

  vpc_cni_role_arn = module.iam.irsa_role_arns["vpc-cni"]
  ebs_csi_role_arn = module.iam.irsa_role_arns["ebs-csi-controller"]

  addon_versions = {
    "vpc-cni"            = "v1.18.2-eksbuild.1"
    "aws-ebs-csi-driver" = "v1.35.0-eksbuild.1"
  }

  tags = {
    Repository = "terraform-eks-modules"
  }
}
```

Lookup uses `null` when a key is absent so AWS selects the default. Do not pass empty strings; an empty version string forces AWS to install that literal value and fails.

## Conflict resolution

EKS add-ons can conflict with existing in-cluster configuration (for example, a manually installed CNI DaemonSet).

| Variable | Default | Behaviour |
|----------|---------|-----------|
| `resolve_conflicts_on_create` | `OVERWRITE` | On first install, replace conflicting fields so the managed add-on can be created |
| `resolve_conflicts_on_update` | `PRESERVE` | On update, keep in-cluster customisations instead of overwriting them |

Use `PRESERVE` on update to avoid wiping Helm values, ConfigMaps, or other changes applied after the initial install. Use `OVERWRITE` on create when migrating from self-managed add-ons.

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.7 |
| aws | ~> 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_name | Project name used for resource naming and tagging | `string` | n/a | yes |
| environment | Deployment environment | `string` | n/a | yes |
| cluster_name | EKS cluster name from the EKS module | `string` | n/a | yes |
| cluster_id | EKS cluster ID from the EKS module; wires dependency on the cluster | `string` | n/a | yes |
| cluster_version | Kubernetes version on the EKS control plane | `string` | n/a | yes |
| vpc_cni_role_arn | IRSA role ARN for the vpc-cni add-on | `string` | n/a | yes |
| ebs_csi_role_arn | IRSA role ARN for the aws-ebs-csi-driver add-on | `string` | n/a | yes |
| addon_versions | Map of add-on name to version; empty map uses AWS defaults | `map(string)` | `{}` | no |
| resolve_conflicts_on_create | Conflict resolution on add-on create | `string` | `"OVERWRITE"` | no |
| resolve_conflicts_on_update | Conflict resolution on add-on update | `string` | `"PRESERVE"` | no |
| tags | Additional resource tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| coredns_arn | ARN of the CoreDNS add-on |
| coredns_version | Installed CoreDNS version |
| vpc_cni_arn | ARN of the vpc-cni add-on |
| vpc_cni_version | Installed vpc-cni version |
| kube_proxy_arn | ARN of the kube-proxy add-on |
| kube_proxy_version | Installed kube-proxy version |
| ebs_csi_arn | ARN of the aws-ebs-csi-driver add-on |
| ebs_csi_version | Installed aws-ebs-csi-driver version |
| addon_arns | Map of add-on name to ARN for all four managed add-ons |

## Apply order

```
global/bootstrap  → once
global/policies   → once
modules/vpc       → environments/dev
modules/iam       → first pass (no IRSA yet)
modules/sg        → environments/dev
modules/eks       → environments/dev
modules/iam       → second pass (IRSA roles available)
modules/addons      → environments/dev (last)
```
