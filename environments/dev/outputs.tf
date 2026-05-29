output "enable_eks" {
  description = "Whether EKS cluster, IRSA, and add-ons are managed by this stack."
  value       = var.enable_eks
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets used by the EKS cluster."
  value       = module.vpc.private_subnet_ids
}

output "cluster_role_arn" {
  description = "IAM role ARN for the EKS control plane (created before the cluster when enable_eks is false)."
  value       = module.iam.cluster_role_arn
}

output "node_role_arn" {
  description = "IAM role ARN for EKS worker nodes."
  value       = module.iam.node_role_arn
}

output "control_plane_sg_id" {
  description = "Security group ID for the EKS control plane."
  value       = module.sg.control_plane_sg_id
}

output "node_sg_id" {
  description = "Security group ID for EKS worker nodes."
  value       = module.sg.node_sg_id
}

output "cluster_name" {
  description = "EKS cluster name (null until enable_eks is true and the cluster exists)."
  value       = var.enable_eks ? module.eks[0].cluster_name : null
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = var.enable_eks ? module.eks[0].cluster_endpoint : null
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = var.enable_eks ? module.eks[0].cluster_version : null
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = var.enable_eks ? module.eks[0].cluster_oidc_issuer_url : null
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = var.enable_eks ? module.eks[0].oidc_provider_arn : null
}

output "node_group_ids" {
  description = "Map of managed node group name to node group ID."
  value       = var.enable_eks ? module.eks[0].node_group_ids : {}
}

output "irsa_role_arns" {
  description = "Map of IRSA role key to IAM role ARN."
  value       = var.enable_eks ? module.iam_irsa[0].irsa_role_arns : {}
}

output "addon_arns" {
  description = "Map of EKS add-on name to add-on ARN."
  value       = var.enable_eks ? module.addons[0].addon_arns : {}
}

output "kms_key_arn" {
  description = "KMS key ARN from bootstrap used for EKS encryption (passthrough for reference)."
  value       = var.state_kms_key_arn
}
