output "enable_eks" {
  description = "Whether all EKS phases are enabled (shortcut for cluster + nodes + IRSA + add-ons)."
  value       = var.enable_eks
}

output "enable_eks_cluster" {
  description = "Whether the EKS control plane module is enabled."
  value       = local.eks_cluster_enabled
}

output "enable_eks_nodes" {
  description = "Whether managed node groups are enabled."
  value       = local.eks_nodes_enabled
}

output "enable_irsa" {
  description = "Whether IRSA roles are enabled."
  value       = local.irsa_enabled
}

output "enable_addons" {
  description = "Whether cluster add-ons (kube-proxy, CoreDNS, EBS CSI) are enabled."
  value       = local.addons_enabled
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
  description = "IAM role ARN for the EKS control plane (created before the cluster when EKS phases are off)."
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
  description = "EKS cluster name (null until phase 1 cluster apply completes)."
  value       = local.eks_cluster_enabled ? module.eks[0].cluster_name : null
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = local.eks_cluster_enabled ? module.eks[0].cluster_endpoint : null
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = local.eks_cluster_enabled ? module.eks[0].cluster_version : null
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = local.eks_cluster_enabled ? module.eks[0].cluster_oidc_issuer_url : null
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = local.eks_cluster_enabled ? module.eks[0].oidc_provider_arn : null
}

output "node_group_ids" {
  description = "Map of managed node group name to node group ID."
  value       = local.eks_nodes_enabled && local.eks_cluster_enabled ? module.eks[0].node_group_ids : {}
}

output "irsa_role_arns" {
  description = "Map of IRSA role key to IAM role ARN."
  value       = local.irsa_enabled && local.eks_cluster_enabled ? module.iam_irsa[0].irsa_role_arns : {}
}

output "addon_arns" {
  description = "Map of EKS add-on name to add-on ARN."
  value       = local.addons_enabled && local.eks_cluster_enabled ? module.addons[0].addon_arns : {}
}

output "kms_key_arn" {
  description = "KMS key ARN from bootstrap used for EKS encryption (passthrough for reference)."
  value       = var.state_kms_key_arn
}
