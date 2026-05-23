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

[`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) runs `terraform fmt`, `validate`, and TFLint on pull requests and pushes to `main`. Optional `terraform plan` against AWS is available via **workflow_dispatch** (requires OIDC; see [bootstrap README](global/bootstrap/README.md#github-actions)).
