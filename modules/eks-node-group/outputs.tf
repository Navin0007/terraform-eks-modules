output "node_group_arn" {
  description = "ARN of the EKS managed node group."
  value       = aws_eks_node_group.this.arn
}

output "node_group_id" {
  description = "ID of the EKS managed node group."
  value       = aws_eks_node_group.this.id
}

output "node_group_status" {
  description = "Status of the EKS managed node group."
  value       = aws_eks_node_group.this.status
}

output "node_iam_role_arn" {
  description = "ARN of the node IAM role (wire into eks-rbac)."
  value       = aws_iam_role.node_group.arn
}

output "node_iam_role_name" {
  description = "Name of the node IAM role (for additional policy attachments)."
  value       = aws_iam_role.node_group.name
}
