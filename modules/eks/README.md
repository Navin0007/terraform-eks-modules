# EKS Module

Provisions an Amazon EKS cluster with managed node groups, OIDC provider, launch templates, optional Fargate profiles, and control plane logging. Consumes networking from the VPC module, IAM roles from the IAM module, security groups from the SG module, and a KMS key from the bootstrap module.

## Design rationale

### IMDSv2 enforcement

Every node group launch template sets `http_tokens = "required"` with `http_put_response_hop_limit = 2` (required for IRSA and standard EKS bootstrap). Nodes attach both the custom node security group and the EKS-managed cluster security group so they can join when using a custom launch template `network_interfaces` block.

### Private API endpoint

`endpoint_private_access` defaults to `true` and `endpoint_public_access` defaults to `false`. The Kubernetes API server is reachable only from within the VPC (for example via bastion, VPN, or private connectivity). Public API exposure expands the attack surface and is disabled unless explicitly overridden with scoped `public_access_cidrs`.

### Secrets encryption

The cluster `encryption_config` block encrypts Kubernetes secrets at rest in etcd using the customer-managed KMS key from bootstrap. Unencrypted etcd secrets fail common compliance controls (SOC 2, PCI, HIPAA) because anyone with etcd access can read Secret objects in plaintext.

### OIDC thumbprint

The IAM OIDC provider thumbprint is fetched at apply time via `data "tls_certificate"` from the cluster issuer URL. Hardcoded thumbprints break when AWS rotates intermediate certificates.

### Cluster Autoscaler compatibility

Each managed node group ignores changes to `scaling_config[0].desired_size`. Cluster Autoscaler adjusts desired capacity based on pending pods; without this lifecycle rule Terraform reverts autoscaler changes on every apply.

## Node group object structure

```hcl
node_groups = {
  general = {
    instance_types = ["m6i.large"]
    capacity_type  = "ON_DEMAND"
    min_size       = 2
    max_size       = 10
    desired_size   = 3
    disk_size_gb   = 100
    labels = {
      role = "general"
    }
    taints = []
    ami_type = "AL2_x86_64"
  }

  spot = {
    instance_types = ["m6i.large", "m5.large"]
    capacity_type  = "SPOT"
    min_size       = 0
    max_size       = 20
    desired_size   = 2
    disk_size_gb   = 80
    labels = {
      role = "spot"
    }
    taints = [{
      key    = "spot"
      value  = "true"
      effect = "NO_SCHEDULE"
    }]
    ami_type = "AL2_x86_64"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.7 |
| aws | ~> 5.0 |
| tls | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_name | Project name used for resource naming and tagging | `string` | n/a | yes |
| environment | Deployment environment | `string` | n/a | yes |
| cluster_name | EKS cluster name for cross-module wiring | `string` | n/a | yes |
| cluster_version | Kubernetes version (for example, 1.29) | `string` | n/a | yes |
| region | AWS region | `string` | n/a | yes |
| vpc_id | VPC ID from the VPC module | `string` | n/a | yes |
| private_subnet_ids | Private subnet IDs from the VPC module | `list(string)` | n/a | yes |
| cluster_role_arn | EKS cluster IAM role ARN from the IAM module | `string` | n/a | yes |
| node_role_arn | EKS node IAM role ARN from the IAM module | `string` | n/a | yes |
| control_plane_sg_id | Control plane security group ID from the SG module | `string` | n/a | yes |
| node_sg_id | Node security group ID from the SG module | `string` | n/a | yes |
| kms_key_arn | KMS key ARN from the bootstrap module | `string` | n/a | yes |
| cluster_log_types | Control plane log types to enable | `list(string)` | `["api", "audit", "authenticator", "controllerManager", "scheduler"]` | no |
| cluster_log_retention_days | CloudWatch log retention in days | `number` | `90` | no |
| endpoint_private_access | Enable private API endpoint | `bool` | `true` | no |
| endpoint_public_access | Enable public API endpoint | `bool` | `false` | no |
| public_access_cidrs | CIDRs allowed when public endpoint is enabled | `list(string)` | `[]` | no |
| node_groups | Managed node group definitions | `map(object)` | `{}` | no |
| fargate_profiles | Fargate profile definitions | `map(object)` | `{}` | no |
| tags | Additional resource tags | `map(string)` | `{}` | no |

`node_groups` object attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| instance_types | `list(string)` | EC2 instance types |
| capacity_type | `string` | `ON_DEMAND` or `SPOT` |
| min_size | `number` | Minimum node count |
| max_size | `number` | Maximum node count |
| desired_size | `number` | Initial desired node count (managed by Cluster Autoscaler after creation) |
| disk_size_gb | `number` | Root EBS volume size in GiB |
| labels | `map(string)` | Kubernetes node labels |
| taints | `list(object)` | Node taints with `key`, `value`, and `effect` |
| ami_type | `string` | EKS AMI type (for example, `AL2_x86_64`) |

`fargate_profiles` object attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| namespace | `string` | Kubernetes namespace selector |
| labels | `map(string)` | Optional pod label selectors |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | EKS cluster ID |
| cluster_name | EKS cluster name |
| cluster_endpoint | Kubernetes API server endpoint |
| cluster_version | Control plane Kubernetes version |
| cluster_oidc_issuer_url | OIDC issuer URL |
| oidc_provider_arn | IAM OIDC provider ARN for IRSA |
| cluster_certificate_authority | Base64-encoded cluster CA data |
| node_group_ids | Map of node group name to ID |
| node_group_arns | Map of node group name to ARN |
| cloudwatch_log_group_name | CloudWatch log group for control plane logs |

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  project_name  = var.project_name
  environment   = var.environment
  cluster_name  = "${var.project_name}-${var.environment}-eks"
  cluster_version = "1.29"
  region        = var.region

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  cluster_role_arn    = module.iam.cluster_role_arn
  node_role_arn       = module.iam.node_role_arn
  control_plane_sg_id = module.sg.control_plane_sg_id
  node_sg_id          = module.sg.node_sg_id
  kms_key_arn         = data.terraform_remote_state.bootstrap.outputs.kms_key_arn

  node_groups = {
    general = {
      instance_types = ["m6i.large"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 10
      desired_size   = 3
      disk_size_gb   = 100
      labels         = { role = "general" }
      taints         = []
      ami_type       = "AL2_x86_64"
    }
  }

  tags = var.tags
}
```

Apply order: bootstrap → VPC → SG → IAM (cluster/node roles) → EKS → IAM (IRSA roles, using EKS OIDC outputs).
