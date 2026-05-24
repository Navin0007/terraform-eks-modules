variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example, dev, staging, prod)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used in security group descriptions and discovery tags."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups are created. Sourced from the VPC module output."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Sourced from the VPC module output. Used for CoreDNS ingress on worker nodes."
  type        = string
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks of private subnets. Sourced from the VPC module for reference and future rule expansion."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks of public subnets. Sourced from the VPC module for reference and future rule expansion."
  type        = list(string)
}

variable "bastion_ingress_cidrs" {
  description = "CIDR blocks allowed to initiate SSH connections to the bastion security group."
  type        = list(string)
  default     = []
}

variable "additional_node_ingress_rules" {
  description = "Extra ingress rules applied to the node security group, keyed by a stable identifier."
  type = map(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags merged into all security groups."
  type        = map(string)
  default     = {}
}
