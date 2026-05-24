# IAM Module

Provisions IAM roles for Amazon EKS: the cluster control plane role and worker node role (created before the cluster), plus optional IRSA roles for Kubernetes service accounts (created after the EKS OIDC provider exists).

## Two-pass apply strategy

EKS requires IAM roles before the cluster can be created, but IRSA roles require the cluster OIDC provider. This module supports both phases in a single root module:

1. **First pass** — Provide cluster and node policy ARNs from `global/policies`. Leave `oidc_provider_arn` and `cluster_oidc_issuer_url` empty (defaults). The module creates only the cluster and node roles.
2. **Second pass** — After `module.eks` exposes OIDC outputs, set `oidc_provider_arn` and `cluster_oidc_issuer_url`, and populate `irsa_roles`. Re-apply to create IRSA roles and policy attachments.

IRSA resources are skipped when `irsa_roles` is empty (first pass). The second pass supplies `irsa_roles` plus `oidc_provider_arn` and `cluster_oidc_issuer_url` from the EKS module.

## IRSA trust policy

Each IRSA role trusts the EKS OIDC provider with `sts:AssumeRoleWithWebIdentity` and two `StringEquals` conditions:

| Condition key | Value |
|---------------|-------|
| `<issuer-host>:sub` | `system:serviceaccount:<namespace>:<service_account>` |
| `<issuer-host>:aud` | `sts.amazonaws.com` |

The issuer host is derived from `cluster_oidc_issuer_url` with the `https://` prefix removed. The `aud` condition prevents tokens minted for other audiences from assuming the role.

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
| cluster_name | EKS cluster name | `string` | n/a | yes |
| aws_account_id | AWS account ID | `string` | n/a | yes |
| region | AWS region | `string` | n/a | yes |
| eks_cluster_policy_arn | Custom EKS cluster policy ARN from global/policies | `string` | n/a | yes |
| eks_node_policy_arn | Custom EKS node policy ARN from global/policies | `string` | n/a | yes |
| eks_autoscaler_policy_arn | Cluster Autoscaler policy ARN from global/policies | `string` | n/a | yes |
| eks_load_balancer_policy_arn | Load Balancer Controller policy ARN from global/policies | `string` | n/a | yes |
| ebs_csi_policy_arn | EBS CSI driver policy ARN from global/policies | `string` | n/a | yes |
| oidc_provider_arn | EKS OIDC provider ARN (second pass) | `string` | `""` | no |
| cluster_oidc_issuer_url | EKS OIDC issuer URL (second pass) | `string` | `""` | no |
| irsa_roles | Map of IRSA roles to create (second pass) | `map(object)` | `{}` | no |
| tags | Additional resource tags | `map(string)` | `{}` | no |

### `irsa_roles` object

| Attribute | Type | Description |
|-----------|------|-------------|
| namespace | `string` | Kubernetes namespace |
| service_account | `string` | Kubernetes service account name |
| policy_arns | `list(string)` | IAM policy ARNs to attach to the role |

## Outputs

| Name | Description |
|------|-------------|
| cluster_role_arn | EKS cluster IAM role ARN |
| cluster_role_name | EKS cluster IAM role name |
| node_role_arn | EKS node IAM role ARN |
| node_role_name | EKS node IAM role name |
| irsa_role_arns | Map of IRSA role key to role ARN |

## Example usage

```hcl
data "terraform_remote_state" "policies" {
  backend = "s3"

  config = {
    bucket = "platform-dev-terraform-state-123456789012"
    key    = "global/policies/terraform.tfstate"
    region = "us-east-1"
  }
}

module "iam" {
  source = "../../modules/iam"

  project_name    = "platform"
  environment     = "dev"
  cluster_name    = "platform-dev"
  aws_account_id  = "123456789012"
  region          = "us-east-1"

  eks_cluster_policy_arn       = data.terraform_remote_state.policies.outputs.eks_cluster_policy_arn
  eks_node_policy_arn          = data.terraform_remote_state.policies.outputs.eks_node_policy_arn
  eks_autoscaler_policy_arn    = data.terraform_remote_state.policies.outputs.eks_autoscaler_policy_arn
  eks_load_balancer_policy_arn = data.terraform_remote_state.policies.outputs.eks_load_balancer_policy_arn
  ebs_csi_policy_arn           = data.terraform_remote_state.policies.outputs.ebs_csi_policy_arn

  oidc_provider_arn       = try(module.eks.oidc_provider_arn, "")
  cluster_oidc_issuer_url = try(module.eks.cluster_oidc_issuer_url, "")

  irsa_roles = {
    cluster-autoscaler = {
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
      policy_arns     = [data.terraform_remote_state.policies.outputs.eks_autoscaler_policy_arn]
    }
    aws-load-balancer-controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      policy_arns     = [data.terraform_remote_state.policies.outputs.eks_load_balancer_policy_arn]
    }
    ebs-csi-controller = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
      policy_arns     = [data.terraform_remote_state.policies.outputs.ebs_csi_policy_arn]
    }
  }

  tags = {
    Repository = "terraform-eks-modules"
  }
}

module "addons" {
  source = "../../modules/addons"

  irsa_role_arns = module.iam.irsa_role_arns
}
```
