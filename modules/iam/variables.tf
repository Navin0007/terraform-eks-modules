variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example, dev, staging, prod)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for IAM role naming."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID where IAM roles are created."
  type        = string
}

variable "region" {
  description = "AWS region where the EKS cluster runs."
  type        = string
}

variable "eks_cluster_policy_arn" {
  description = "ARN of the custom EKS cluster IAM policy from global/policies."
  type        = string
}

variable "eks_node_policy_arn" {
  description = "ARN of the custom EKS node IAM policy from global/policies."
  type        = string
}

variable "eks_autoscaler_policy_arn" {
  description = "ARN of the Cluster Autoscaler IAM policy from global/policies."
  type        = string
}

variable "eks_load_balancer_policy_arn" {
  description = "ARN of the AWS Load Balancer Controller IAM policy from global/policies."
  type        = string
}

variable "ebs_csi_policy_arn" {
  description = "ARN of the EBS CSI driver IAM policy from global/policies."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider. Empty on the first apply before the cluster exists."
  type        = string
  default     = ""
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster. Empty on the first apply before the cluster exists."
  type        = string
  default     = ""
}

variable "create_core_roles" {
  description = "Whether to create the EKS cluster and node IAM roles. Set to false on the IRSA-only second module pass."
  type        = bool
  default     = true
}

variable "irsa_roles" {
  description = "Map of IRSA roles to create after the EKS OIDC provider is available."
  type = map(object({
    namespace       = string
    service_account = string
    policy_arns     = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags to apply to all IAM resources."
  type        = map(string)
  default     = {}
}
