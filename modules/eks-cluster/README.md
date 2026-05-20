# eks-cluster

Creates an EKS control plane with cluster IAM role, OIDC provider for IRSA, and CloudWatch control plane logging.

## Usage

```hcl
module "cluster" {
  source = "git::https://github.com/Navin0007/terraform-eks-modules.git//modules/eks-cluster?ref=v1.0.0"

  cluster_name      = "my-cluster"
  cluster_version   = "1.29"
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  cluster_log_types = ["api", "audit", "authenticator"]
  tags              = local.tags
}
```

## Outputs

Wire `cluster_endpoint`, `cluster_ca_certificate`, and `oidc_provider_arn` into downstream modules (node group, addons, RBAC).
