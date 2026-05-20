variable "cluster_name" {
  description = "Name of the EKS cluster to attach the node group to."
  type        = string
}

variable "node_group_name" {
  description = "Name of the managed node group."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for worker nodes (typically private subnets)."
  type        = list(string)
}

variable "instance_types" {
  description = "EC2 instance types for the node group."
  type        = list(string)
}

variable "disk_size_gb" {
  description = "Root volume size in GiB for worker nodes."
  type        = number
  default     = 50
}

variable "min_size" {
  description = "Minimum number of nodes in the autoscaling group."
  type        = number
}

variable "max_size" {
  description = "Maximum number of nodes in the autoscaling group."
  type        = number
}

variable "desired_size" {
  description = "Desired number of nodes in the autoscaling group."
  type        = number
}

variable "ami_type" {
  description = "AMI type for the node group (e.g. AL2_x86_64, AL2023_x86_64_STANDARD)."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
