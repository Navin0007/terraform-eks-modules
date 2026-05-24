# VPC Module

Provisions networking infrastructure for Amazon EKS: a VPC, public and private subnets across multiple availability zones, NAT gateways, routing, and gateway VPC endpoints for S3 and DynamoDB.

## Subnet tagging for EKS

Subnets are tagged so the AWS cloud provider and load balancer controller can discover them:

| Subnet type | Tags |
|-------------|------|
| Private | `kubernetes.io/role/internal-elb = 1`, `kubernetes.io/cluster/<cluster_name> = shared` |
| Public | `kubernetes.io/role/elb = 1`, `kubernetes.io/cluster/<cluster_name> = shared` |

The `shared` cluster tag allows multiple clusters to use the same subnets. Internal load balancers are placed in private subnets; internet-facing load balancers use public subnets.

## NAT gateway options

| Setting | Behavior |
|---------|----------|
| `enable_nat_gateway = false` | No NAT gateways; private subnets have no default route to the internet. |
| `single_nat_gateway = true` | One NAT gateway in the first public subnet; all private subnets share it (lower cost, single-AZ egress failure domain). |
| `single_nat_gateway = false` (default) | One NAT gateway per availability zone (`one_nat_gateway_per_az = true`). |

Set `single_nat_gateway = true` in dev via `terraform.tfvars` to reduce cost. Production should keep the default `false` for AZ-level resilience.

## Gateway VPC endpoints

S3 and DynamoDB use **gateway** endpoints (not interface endpoints). Gateway endpoints are free and route traffic over the AWS network, avoiding NAT charges for Terraform state and DynamoDB lock traffic from private subnets.

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
| region | AWS region | `string` | n/a | yes |
| vpc_cidr | VPC CIDR block | `string` | n/a | yes |
| azs | Availability zones to deploy into | `list(string)` | n/a | yes |
| private_subnet_cidrs | Private subnet CIDRs, one per AZ | `list(string)` | n/a | yes |
| public_subnet_cidrs | Public subnet CIDRs, one per AZ | `list(string)` | n/a | yes |
| cluster_name | EKS cluster name for subnet discovery tags | `string` | n/a | yes |
| enable_nat_gateway | Create NAT gateways | `bool` | `true` | no |
| single_nat_gateway | Use one shared NAT gateway | `bool` | `false` | no |
| enable_vpn_gateway | Create a VPN gateway | `bool` | `false` | no |
| enable_dns_hostnames | Enable DNS hostnames on the VPC | `bool` | `true` | no |
| enable_dns_support | Enable DNS support on the VPC | `bool` | `true` | no |
| tags | Additional resource tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | VPC ID |
| vpc_cidr_block | VPC CIDR block |
| private_subnet_ids | Private subnet IDs |
| public_subnet_ids | Public subnet IDs |
| nat_gateway_ids | NAT gateway IDs |
| private_route_table_ids | Private route table IDs |
| public_route_table_ids | Public route table IDs |
| s3_vpc_endpoint_id | S3 gateway VPC endpoint ID |

## Example usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project_name = "platform"
  environment  = "dev"
  region       = "us-east-1"

  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  cluster_name         = "platform-dev"

  single_nat_gateway = true

  tags = {
    Repository = "terraform-eks-modules"
  }
}
```
