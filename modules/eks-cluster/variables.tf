variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS control plane (private subnets recommended)."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID where the cluster security group is created."
  type        = string
}

variable "cluster_log_types" {
  description = "Control plane log types to enable (api, audit, authenticator, controllerManager, scheduler)."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
