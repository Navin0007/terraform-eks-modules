variable "cluster_name" {
  description = "Name of the EKS cluster (used for resource naming context)."
  type        = string
}

variable "node_iam_role_arn" {
  description = "IAM role ARN for worker nodes (from eks-node-group module)."
  type        = string
}

variable "additional_iam_roles" {
  description = "Additional IAM roles to map into Kubernetes RBAC via aws-auth."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}
