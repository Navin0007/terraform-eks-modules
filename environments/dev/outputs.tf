output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of private subnets used by the EKS cluster."
  value       = module.vpc.private_subnet_ids
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = module.eks.cluster_version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "node_group_ids" {
  description = "Map of managed node group name to node group ID."
  value       = module.eks.node_group_ids
}

output "irsa_role_arns" {
  description = "Map of IRSA role key to IAM role ARN."
  value       = module.iam_irsa.irsa_role_arns
}

output "addon_arns" {
  description = "Map of EKS add-on name to add-on ARN."
  value       = module.addons.addon_arns
}

output "kms_key_arn" {
  description = "KMS key ARN from bootstrap used for EKS encryption (passthrough for reference)."
  value       = var.state_kms_key_arn
}
