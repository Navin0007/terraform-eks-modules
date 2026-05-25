variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example, dev, staging, prod)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for cross-module wiring (must match {project_name}-{environment}-eks)."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane (for example, 1.29). Use lifecycle ignore_changes on the cluster for imports."
  type        = string
}

variable "authentication_mode" {
  description = "EKS authentication mode. Leave null for existing clusters (avoids forced replacement). Use API_AND_CONFIG_MAP for new clusters with access entries."
  type        = string
  default     = null

  validation {
    condition = (
      var.authentication_mode == null
      ? true
      : contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    )
    error_message = "authentication_mode must be API, API_AND_CONFIG_MAP, or CONFIG_MAP."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Grant cluster-creator admin when setting authentication_mode on a new cluster."
  type        = bool
  default     = true
}

variable "region" {
  description = "AWS region where the EKS cluster is created."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID from the VPC module."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from the VPC module for control plane and worker placement."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least two private subnets are required for EKS high availability."
  }
}

variable "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role from the IAM module."
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the EKS node IAM role from the IAM module."
  type        = string
}

variable "control_plane_sg_id" {
  description = "Security group ID for the EKS control plane from the SG module."
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID for EKS worker nodes from the SG module."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN from the bootstrap module for secrets and node volume encryption."
  type        = string
}

variable "cluster_log_types" {
  description = "Control plane log types to enable."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "Retention period in days for EKS control plane CloudWatch logs."
  type        = number
  default     = 90
}

variable "endpoint_private_access" {
  description = "Whether the Kubernetes API server is reachable from within the VPC."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the Kubernetes API server is reachable from the public internet."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public Kubernetes API endpoint when endpoint_public_access is true."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "manage_aws_auth_configmap" {
  description = "Manage the kube-system aws-auth ConfigMap (required for managed nodes when authentication mode is API_AND_CONFIG_MAP)."
  type        = bool
  default     = true
}

variable "aws_auth_map_roles" {
  description = "Additional mapRoles entries for the aws-auth ConfigMap (node role is added automatically)."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "aws_auth_map_users" {
  description = "mapUsers entries for the aws-auth ConfigMap."
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default = []
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
  default = {}

  validation {
    condition = alltrue([
      for name, group in var.node_groups :
      contains(["ON_DEMAND", "SPOT"], group.capacity_type)
    ])
    error_message = "Each node group capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition = alltrue([
      for name, group in var.node_groups :
      group.min_size >= 0 && group.max_size >= group.min_size && group.desired_size >= group.min_size && group.desired_size <= group.max_size
    ])
    error_message = "Node group scaling bounds must satisfy min_size <= desired_size <= max_size."
  }

  validation {
    condition = alltrue([
      for name, group in var.node_groups :
      alltrue([
        for taint in group.taints :
        contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], taint.effect)
      ])
    ])
    error_message = "Node group taint effect must be NO_SCHEDULE, NO_EXECUTE, or PREFER_NO_SCHEDULE."
  }
}

variable "fargate_profiles" {
  description = "Fargate profiles keyed by profile name."
  type = map(object({
    namespace = string
    labels    = map(string)
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags to apply to all EKS resources."
  type        = map(string)
  default     = {}
}
