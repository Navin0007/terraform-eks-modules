output "node_group_arn" {
  description = "ARN of the EKS managed node group."
  value       = aws_eks_node_group.this.arn
}

output "node_group_status" {
  description = "Status of the EKS managed node group."
  value       = aws_eks_node_group.this.status
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role used by worker nodes (for aws-auth mapping)."
  value       = aws_iam_role.node.arn
}
