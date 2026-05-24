# Bootstrap

Foundational AWS infrastructure for Terraform remote state. Apply this module **once per AWS account and environment** before any other Terraform configuration in this repository. It uses a **local backend** on first apply; downstream environments consume the outputs to configure S3/DynamoDB remote backends.

## Purpose

- Provision a dedicated S3 bucket for encrypted, versioned Terraform state
- Provision a DynamoDB table for state locking
- Provision a customer-managed KMS key and alias for encryption at rest

Without this module, other stacks cannot safely share remote state or coordinate concurrent applies.

## Resources created

| Resource | Description |
|----------|-------------|
| `aws_kms_key` | Customer-managed key with rotation enabled (10-day deletion window) |
| `aws_kms_alias` | `alias/{project_name}-{environment}-terraform-state` |
| `aws_s3_bucket` | Remote state bucket (`force_destroy = false`) |
| `aws_s3_bucket_versioning` | Versioning enabled |
| `aws_s3_bucket_server_side_encryption_configuration` | SSE-KMS using the bootstrap key |
| `aws_s3_bucket_public_access_block` | All public access settings blocked |
| `aws_dynamodb_table` | Lock table (`LockID` string hash key, on-demand billing, SSE-KMS) |

Naming (derived from inputs):

- S3 bucket: `{project_name}-{environment}-terraform-state-{aws_account_id}`
- DynamoDB table: `{project_name}-{environment}-terraform-locks`

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | `string` | Short project name used in resource naming and tags |
| `environment` | `string` | Environment label (for example `dev`, `staging`, `prod`) |
| `region` | `string` | AWS region for all bootstrap resources |
| `aws_account_id` | `string` | 12-digit AWS account ID (used in bucket name and KMS policy) |

## Outputs

| Name | Description |
|------|-------------|
| `state_bucket_name` | S3 bucket name for remote state |
| `state_bucket_arn` | S3 bucket ARN |
| `dynamodb_table_name` | DynamoDB lock table name |
| `kms_key_arn` | KMS key ARN for backend `encrypt` configuration |
| `kms_key_id` | KMS key ID |

## How to apply

**Prerequisites:** AWS credentials with permissions to create KMS keys, S3 buckets, and DynamoDB tables in the target account and region. Terraform `~> 1.7` and AWS provider `~> 5.0`.

1. Change into this directory:

   ```bash
   cd global/bootstrap
   ```

2. Create a variable file (do not commit secrets; adjust values for your account):

   ```hcl
   # terraform.tfvars
   project_name   = "my-project"
   environment    = "prod"
   region         = "us-east-1"
   aws_account_id = "123456789012"
   ```

3. Initialize and apply (local state is stored in this directory until you optionally migrate it):

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. Record the outputs. Use them in environment backends, for example:

   ```hcl
   terraform {
     backend "s3" {
       bucket         = "<state_bucket_name output>"
       key            = "environments/prod/terraform.tfstate"
       region         = "<region variable>"
       dynamodb_table = "<dynamodb_table_name output>"
       encrypt        = true
       kms_key_id     = "<kms_key_arn output>"
     }
   }
   ```

5. Grant IAM principals that run Terraform `s3:*` on the state bucket, `dynamodb:*` on the lock table (scoped as needed), and `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey`, and `kms:DescribeKey` on the KMS key.

Re-run `terraform plan` after changes; bootstrap updates are rare and should be reviewed carefully because they affect all dependent environments.

## GitHub Actions

The workflow [`.github/workflows/terraform.yml`](../../.github/workflows/terraform.yml) runs on pull requests and pushes that change Terraform files.

| Job | When | AWS required |
|-----|------|----------------|
| **Format** | Every PR / push to `main` | No |
| **Validate** | Every PR / push to `main` | No — `global/bootstrap`, `global/policies`, `environments/dev` |
| **TFLint** | Every PR / push to `main` | No |
| **Plan / Apply** | Manual: Actions → Terraform → Run workflow | Yes — OIDC |

### Deploy order in CI (`target: all`)

1. **Bootstrap** — local backend on first apply, then state migrates to `s3://…/global/bootstrap/terraform.tfstate`
2. **Policies** — `global/policies/terraform.tfstate`
3. **Dev** — `dev/terraform.tfstate`

Use **operation** `apply` for the full stack or `plan` to preview. Narrow **target** to a single root when needed.

### Repository setup

1. IAM role for GitHub OIDC (trust `token.actions.githubusercontent.com`, subject scoped to this repo).
2. Policy: permissions for bootstrap (KMS, S3, DynamoDB), policies (IAM), and dev (VPC, EKS, IAM, etc.).
3. **Settings → Secrets and variables → Actions**
   - Secret: `AWS_ROLE_ARN`
   - Variables (required): `AWS_REGION`, `AWS_ACCOUNT_ID`, `TF_PROJECT_NAME`, `TF_ENVIRONMENT` (for example `dev`)
   - Variables (after first bootstrap apply, for plan-only runs): `TF_STATE_BUCKET`, `TF_STATE_KMS_KEY_ID`, `TF_STATE_DYNAMODB_TABLE`, `TF_STATE_KMS_KEY_ARN`
4. Optional GitHub **environment** named `dev` (workflow uses `TF_ENVIRONMENT`) for approval gates on apply.

On the first **apply** with `target: all`, the workflow prints bootstrap output values; copy them into the `TF_STATE_*` repository variables so later plan runs can init policies and dev without re-applying bootstrap.
