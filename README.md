# terraform-eks-modules

Terraform modules for EKS infrastructure on AWS.

## Modules

| Module | Purpose |
|--------|---------|
| [vpc](modules/vpc) | VPC, subnets, routing |
| [eks](modules/eks) | EKS control plane and node groups |
| [iam](modules/iam) | IAM roles and IRSA |
| [sg](modules/sg) | Security groups |
| [addons](modules/addons) | Cluster add-ons |
| [bootstrap](global/bootstrap) | Remote state bootstrap (S3, DynamoDB, KMS) |
| [policies](global/policies) | Shared IAM managed policies for EKS and add-ons |

## Usage

```hcl
module "eks" {
  source  = "git::https://github.com/Navin0007/terraform-eks-modules.git//modules/eks"
  version = "~> 0.0"
}
```

## CI

[`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) runs `terraform fmt`, `validate`, and TFLint on pull requests and pushes to `main`.

**Deploy via GitHub Actions:** Actions → **Terraform** → Run workflow.

| Operation | Target | Order |
|-----------|--------|--------|
| `plan` / `apply` | `all` | `global/bootstrap` → `global/policies` → `environments/dev` |
| `destroy` | `all` | `environments/dev` → `global/policies` → `global/bootstrap` (reverse) |
| `destroy` | `environments/dev` | EKS/VPC/dev only (keeps bootstrap + policies) |

**Destroy:** set **operation** to `destroy`, type `destroy` in **confirm_destroy**, then run. Dev destroy scales down and deletes the node group first. Destroying bootstrap empties the remote state S3 bucket, then removes the bucket, lock table, and KMS key. Destroy/plan discover the state bucket from AWS if repository variables are not set (bootstrap must have been applied once).

Requires OIDC (`AWS_ROLE_ARN` secret) and repository variables — see [bootstrap README](global/bootstrap/README.md#github-actions).
