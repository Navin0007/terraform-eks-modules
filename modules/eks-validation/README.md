# eks-validation

Post-apply validation for EKS clusters using `aws` CLI and `kubectl`.

## Usage

```hcl
module "eks_validation" {
  source = "../eks-validation"

  cluster_name = module.eks.cluster_name
  region       = var.region

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  node_role_arn      = module.iam.node_role_arn

  depends_on = [module.eks_node_groups, module.addons]
}
```

See [docs/EKS-POST-APPLY-VALIDATION.md](../../docs/EKS-POST-APPLY-VALIDATION.md) for the full checklist.

## Requirements

- `aws`, `kubectl`, `curl`, `python3` on the machine running `terraform apply`
- IAM permissions for EKS, EC2, IAM, CloudWatch Logs
- Network path to the Kubernetes API (public or private endpoint)
