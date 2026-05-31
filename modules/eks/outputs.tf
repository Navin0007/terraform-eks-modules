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

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for EKS control plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}
