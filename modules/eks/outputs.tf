output "cluster_id" {
  description = "EKS cluster ID."
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane."
  value       = aws_eks_cluster.main.version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data for kubectl and cluster authentication."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_group_ids" {
  description = "Map of node group name to node group ID."
  value = {
    for name, group in aws_eks_node_group.main : name => group.id
  }
}

output "node_group_arns" {
  description = "Map of node group name to node group ARN."
  value = {
    for name, group in aws_eks_node_group.main : name => group.arn
  }
}

output "nodes_joined" {
  description = "Set after node group scale-out and Ready node verification (gates add-on install)."
  value       = var.enable_node_groups ? join(",", [for _, r in null_resource.node_group_scale_out : r.id]) : ""
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for EKS control plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}

output "vpc_cni_addon_arn" {
  description = "ARN of the vpc-cni add-on installed before node groups."
  value       = aws_eks_addon.vpc_cni.arn
}
