variable "cluster_name" {
  description = "EKS cluster name (from eks-cluster module output)."
  type        = string
}

variable "node_group_name" {
  description = "Unique managed node group name within the cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for worker nodes."
  type        = list(string)
}

variable "instance_types" {
  description = "EC2 instance types for the node group (e.g. [\"t3.medium\"])."
  type        = list(string)
}

variable "ami_type" {
  description = "EKS-managed AMI type for the node group."
  type        = string
  default     = "AL2_x86_64"
}

variable "disk_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 20
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

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
