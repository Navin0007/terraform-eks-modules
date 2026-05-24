variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example, dev, staging, prod)."
  type        = string
}

variable "region" {
  description = "AWS region where the VPC and related networking resources are created."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability zone names to deploy subnets and NAT gateways into."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per availability zone."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per availability zone."
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name used for Kubernetes subnet discovery tags."
  type        = string
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateways for private subnet egress."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT gateway across all private subnets (set true in dev to reduce cost)."
  type        = bool
  default     = false
}

variable "enable_vpn_gateway" {
  description = "Whether to create and attach a VPN gateway to the VPC."
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Whether DNS hostnames are enabled for the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Whether DNS resolution is enabled for the VPC."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all VPC resources."
  type        = map(string)
  default     = {}
}
