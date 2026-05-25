variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example, dev, staging, prod)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name from the EKS module."
  type        = string
}

variable "cluster_id" {
  description = "EKS cluster ID from the EKS module output; wires an explicit dependency on the cluster before add-on installation."
  type        = string
}

variable "nodes_ready_dependency" {
  description = "EKS module nodes_joined output; add-ons wait until nodes are Ready before install."
  type        = string
  default     = ""
}

variable "cluster_version" {
  description = "Kubernetes version running on the EKS control plane from the EKS module output."
  type        = string
}

variable "vpc_cni_role_arn" {
  description = "IRSA role ARN for the vpc-cni add-on from the IAM module irsa_role_arns map."
  type        = string
}

variable "install_vpc_cni_addon" {
  description = "Create the vpc-cni add-on in this module. Set false when module.eks already installed vpc-cni before node groups."
  type        = bool
  default     = true
}

variable "ebs_csi_role_arn" {
  description = "IRSA role ARN for the aws-ebs-csi-driver add-on from the IAM module irsa_role_arns map."
  type        = string
}

variable "addon_versions" {
  description = "Optional map of EKS add-on name to version string. Omit keys or leave the map empty to let AWS install the default version for the cluster Kubernetes version."
  type        = map(string)
  default     = {}
}

variable "resolve_conflicts_on_create" {
  description = "How to resolve field value conflicts when creating an add-on. Valid values are OVERWRITE and NONE."
  type        = string
  default     = "OVERWRITE"

  validation {
    condition     = contains(["OVERWRITE", "NONE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be OVERWRITE or NONE."
  }
}

variable "resolve_conflicts_on_update" {
  description = "How to resolve field value conflicts when updating an add-on. Valid values are OVERWRITE, PRESERVE, and NONE."
  type        = string
  default     = "PRESERVE"

  validation {
    condition     = contains(["OVERWRITE", "PRESERVE", "NONE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be OVERWRITE, PRESERVE, or NONE."
  }
}

variable "tags" {
  description = "Additional tags applied to all add-on resources."
  type        = map(string)
  default     = {}
}
