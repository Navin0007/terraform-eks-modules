# Security Groups Module

Provisions the security groups required for an Amazon EKS cluster. Apply this module before the EKS module so control plane, node, bastion, and pod security groups exist and can be referenced independently of cluster lifecycle operations.

## Design rationale

Security groups are separated from the EKS module so they can be reasoned about, audited, and modified without touching cluster resources. Cluster-to-node and node-to-node traffic uses security group references instead of CIDR blocks where possible, which keeps rules precise as the VPC grows. The pod security group is intentionally empty on ingress: workloads using Security Groups for Pods attach their own rules. Node egress remains open to the internet so nodes can reach ECR, S3, and AWS APIs through NAT without per-service rule churn.

## Port reference

### Control plane security group

| Direction | Source | Destination | Port | Protocol | Reason |
|-----------|--------|-------------|------|----------|--------|
| Ingress | Node SG | Control plane SG | 443 | TCP | Kubelet to API server |
| Ingress | Bastion SG | Control plane SG | 443 | TCP | kubectl from bastion |
| Egress | Control plane SG | Node SG | 1025–65535 | TCP | API server to kubelet |
| Egress | Control plane SG | Node SG | 443 | TCP | API server webhooks |

### Node security group

| Direction | Source | Destination | Port | Protocol | Reason |
|-----------|--------|-------------|------|----------|--------|
| Ingress | Control plane SG | Node SG | 1025–65535 | TCP | Kubelet and NodePort |
| Ingress | Control plane SG | Node SG | 443 | TCP | API server to node metrics |
| Ingress | Node SG | Node SG | All | All | Node-to-node communication |
| Ingress | VPC CIDR | Node SG | 53 | UDP | CoreDNS |
| Ingress | VPC CIDR | Node SG | 53 | TCP | CoreDNS |
| Egress | Node SG | 0.0.0.0/0 | All | All | ECR, S3, and AWS API access |

Additional ingress rules can be supplied via `additional_node_ingress_rules`.

### Bastion security group

| Direction | Source | Destination | Port | Protocol | Reason |
|-----------|--------|-------------|------|----------|--------|
| Ingress | `bastion_ingress_cidrs` | Bastion SG | 22 | TCP | SSH access |
| Egress | Bastion SG | Control plane SG | 443 | TCP | kubectl to API server |
| Egress | Bastion SG | 0.0.0.0/0 | 443 | TCP | HTTPS outbound |
| Egress | Bastion SG | 0.0.0.0/0 | 80 | TCP | HTTP for package installs |

### Pod security group

| Direction | Source | Destination | Port | Protocol | Reason |
|-----------|--------|-------------|------|----------|--------|
| Ingress | — | Pod SG | — | — | None by default; workloads add rules |
| Egress | Pod SG | 0.0.0.0/0 | All | All | Pod outbound traffic |

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
| vpc_id | VPC ID from the VPC module | `string` | n/a | yes |
| vpc_cidr | VPC CIDR from the VPC module | `string` | n/a | yes |
| private_subnet_cidrs | Private subnet CIDRs from the VPC module | `list(string)` | n/a | yes |
| public_subnet_cidrs | Public subnet CIDRs from the VPC module | `list(string)` | n/a | yes |
| bastion_ingress_cidrs | CIDRs allowed to SSH to the bastion | `list(string)` | `[]` | no |
| additional_node_ingress_rules | Extra node ingress rules | `map(object)` | `{}` | no |
| tags | Additional resource tags | `map(string)` | `{}` | no |

`additional_node_ingress_rules` object shape:

| Attribute | Type |
|-----------|------|
| from_port | `number` |
| to_port | `number` |
| protocol | `string` |
| cidr_blocks | `list(string)` |
| description | `string` |

## Outputs

| Name | Description |
|------|-------------|
| control_plane_sg_id | Control plane security group ID |
| node_sg_id | Worker node security group ID |
| bastion_sg_id | Bastion security group ID |
| pod_sg_id | Pod security group ID |

## Example usage

```hcl
module "vpc" {
  source = "../../modules/vpc"
  # ...
}

module "sg" {
  source = "../../modules/sg"

  project_name = "platform"
  environment  = "prod"
  cluster_name = "platform-prod"

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr_block
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  bastion_ingress_cidrs = ["203.0.113.10/32"]

  additional_node_ingress_rules = {
    metrics-scrape = {
      from_port   = 9100
      to_port     = 9100
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
      description = "Prometheus node exporter scrape"
    }
  }

  tags = {
    Team = "platform"
  }
}
```
