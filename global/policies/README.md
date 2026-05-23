# Policies

Shared IAM managed policies for EKS and related controllers. Apply this module **once per AWS account and environment** (or whenever policy documents change). It creates **managed policies only** — no IAM roles. Other modules attach these policies to roles via `aws_iam_role_policy_attachment` or IRSA trust policies.

## Purpose

- Centralize least-privilege policy documents for EKS control plane, worker nodes, Cluster Autoscaler, AWS Load Balancer Controller, and the EBS CSI driver
- Keep naming and tagging consistent across environments (`{project_name}-{environment}-*`)
- Expose stable ARNs for downstream modules (EKS, IAM, add-ons)

## Policies created

| Policy | IAM name | Permissions summary |
|--------|----------|---------------------|
| EKS cluster | `{project_name}-{environment}-eks-cluster` | `eks:Describe*`, `eks:List*`, `eks:AccessKubernetesApi`; CloudWatch Logs create group/stream and put events |
| EKS node | `{project_name}-{environment}-eks-node` | `ec2:Describe*`; ECR pull (`GetAuthorizationToken`, `BatchCheckLayerAvailability`, `GetDownloadUrlForLayer`, `BatchGetImage`) |
| EKS autoscaler | `{project_name}-{environment}-eks-autoscaler` | Auto Scaling describe and scale/terminate; `ec2:DescribeLaunchTemplateVersions` |
| EKS load balancer | `{project_name}-{environment}-eks-load-balancer` | `elasticloadbalancing:*`; EC2 describe APIs for VPC/subnet/SG/instance/networking; `iam:CreateServiceLinkedRole` for ELB service only |
| EBS CSI | `{project_name}-{environment}-ebs-csi` | EBS volume attach/detach/modify/snapshot and describe APIs; KMS grant and encryption APIs |

All policy documents are built with `data "aws_iam_policy_document"` blocks (no inline JSON strings). Every managed policy is tagged with `managed_by = "terraform"` (plus `Project`, `Environment`, and `Name`).

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | `string` | Short project name used in policy naming and tags |
| `environment` | `string` | Environment label (for example `dev`, `staging`, `prod`) |
| `aws_account_id` | `string` | 12-digit AWS account ID (for consistency with other global modules) |
| `region` | `string` | AWS region for the provider |

## Outputs

| Name | Description |
|------|-------------|
| `eks_cluster_policy_arn` | ARN of the EKS cluster policy |
| `eks_node_policy_arn` | ARN of the EKS node policy |
| `eks_autoscaler_policy_arn` | ARN of the Cluster Autoscaler policy |
| `eks_load_balancer_policy_arn` | ARN of the load balancer controller policy |
| `ebs_csi_policy_arn` | ARN of the EBS CSI driver policy |

## How to apply

**Prerequisites:** AWS credentials with `iam:CreatePolicy`, `iam:GetPolicy`, `iam:ListPolicyVersions`, and `iam:TagPolicy` in the target account. Terraform `~> 1.7` and AWS provider `~> 5.0`. Bootstrap ([`global/bootstrap`](../bootstrap)) should already exist if you use remote state for other stacks.

1. Change into this directory:

   ```bash
   cd global/policies
   ```

2. Create a variable file (adjust for your account; do not commit secrets):

   ```hcl
   # terraform.tfvars
   project_name   = "my-project"
   environment    = "prod"
   region         = "us-east-1"
   aws_account_id = "123456789012"
   ```

3. Configure a backend if desired (for example, outputs from bootstrap), then initialize and apply:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. Pass output ARNs into environment or service modules, for example:

   ```hcl
   resource "aws_iam_role_policy_attachment" "cluster" {
     role       = aws_iam_role.eks_cluster.name
     policy_arn = var.eks_cluster_policy_arn
   }
   ```

5. Re-run `terraform plan` after policy changes. Updating a managed policy creates a new policy version; roles using the policy pick up the default version on the next evaluation.

Policy updates are infrequent but affect every role that attaches them — review plans carefully in production accounts.

## GitHub Actions

The workflow [`.github/workflows/terraform.yml`](../../.github/workflows/terraform.yml) runs on pull requests and pushes that change Terraform files.

| Job | When | AWS required |
|-----|------|----------------|
| **Format** | Every PR / push to `main` | No — `terraform fmt -check -recursive` |
| **Validate** | Every PR / push to `main` | No — `terraform init` and `validate` for `global/bootstrap` and `global/policies` |
| **TFLint** | Every PR / push to `main` | No |
| **Plan** | Manual: Actions → Terraform → Run workflow, choose **global/policies**, enable **Run terraform plan** | Yes — OIDC role and repository variables |

For optional plan jobs, create a GitHub **environment** named `policies` (or reuse `bootstrap` in a sandbox) with the same `AWS_ROLE_ARN`, `AWS_REGION`, `AWS_ACCOUNT_ID`, `TF_PROJECT_NAME`, and `TF_ENVIRONMENT` variables as bootstrap.
