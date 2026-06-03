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
| [eks-validation](modules/eks-validation) | Post-apply `aws`/`kubectl` health checks |
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

[`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) runs `terraform fmt`, `validate`, and TFLint on pull requests and pushes to `main`. Every dev stack **apply** in Actions (workflow dispatch) runs [EKS post-apply validation](docs/EKS-POST-APPLY-VALIDATION.md) immediately afterward; the job fails if checks fail.

**Deploy via GitHub Actions:** Actions → **Terraform** → Run workflow.

| Operation | Target | Order |
|-----------|--------|--------|
| `plan` / `apply` | `all` | `global/bootstrap` → `global/policies` → `environments/dev` |
| `destroy` | `all` | `environments/dev` → `global/policies` → `global/bootstrap` (reverse) |
| `destroy` | `environments/dev` | EKS/VPC/dev only (keeps bootstrap + policies) |

**Destroy:** set **operation** to `destroy`, type `destroy` in **confirm_destroy**, then run. Dev destroy scales down and deletes the node group first. Bootstrap destroy uses `state_bucket_force_destroy=true` so the state bucket can be removed with objects still inside. Destroy/plan discover the state bucket from AWS if repository variables are not set.

If you see an S3/DynamoDB state checksum error after a failed destroy, re-run **destroy** with target `global/bootstrap` (or `all`); the workflow deletes digest rows (`{bucket}/{key}-md5`) and re-syncs the digest from S3 before init.

Requires OIDC (`AWS_ROLE_ARN` secret) and repository variables — see [bootstrap README](global/bootstrap/README.md#github-actions).
