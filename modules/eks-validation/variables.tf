variable "enabled" {
  description = "Run post-apply validation after dependencies are satisfied."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "cluster_version" {
  description = "Expected Kubernetes control plane version."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "Expected VPC ID attached to the cluster."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "VPC CIDR for overlap checks."
  type        = string
  default     = null
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for tag validation."
  type        = list(string)
  default     = []
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for tag validation."
  type        = list(string)
  default     = []
}

variable "cluster_role_arn" {
  description = "EKS cluster IAM role ARN."
  type        = string
  default     = null
}

variable "node_role_arn" {
  description = "EKS node IAM role ARN."
  type        = string
  default     = null
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA."
  type        = string
  default     = null
}

variable "control_plane_sg_id" {
  description = "Control plane security group ID."
  type        = string
  default     = null
}

variable "cloudwatch_log_group" {
  description = "CloudWatch log group for control plane logs."
  type        = string
  default     = null
}

variable "nodegroup_names" {
  description = "Managed node group names to validate."
  type        = list(string)
  default     = ["general"]
}

variable "ebs_csi_role_arn" {
  description = "IRSA role ARN for the EBS CSI driver (when post-node add-ons are enabled)."
  type        = string
  default     = null
}

variable "validate_post_node_addons" {
  description = "Run CoreDNS, EBS CSI, storage, and extended DNS checks."
  type        = bool
  default     = false
}

variable "validate_pvc_test" {
  description = "Create and delete a test PVC (requires EBS CSI and default StorageClass)."
  type        = bool
  default     = false
}

variable "allow_public_world_cidr" {
  description = "Do not fail when publicAccessCidrs includes 0.0.0.0/0 (common in dev)."
  type        = bool
  default     = false
}

variable "skip_categories" {
  description = "Comma-separated category skips: networking, nodes, iam, addons, pod_networking, storage, logging, security, tagging."
  type        = string
  default     = ""
}

variable "validation_triggers" {
  description = "Additional values hashed into null_resource triggers (e.g. addon ARNs, node group IDs)."
  type        = string
  default     = ""
}
