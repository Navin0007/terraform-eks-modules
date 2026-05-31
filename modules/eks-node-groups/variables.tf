variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for node group placement."
  type        = list(string)
}

variable "node_role_arn" {
  description = "IAM role ARN for managed node instances."
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID for worker nodes."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for node volume encryption."
  type        = string
}

variable "node_groups" {
  description = "Managed node groups keyed by group name."
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size_gb   = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
    ami_type = string
  }))
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
