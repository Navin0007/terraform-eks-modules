output "eks_cluster_policy_arn" {
  description = "ARN of the EKS cluster managed IAM policy."
  value       = aws_iam_policy.eks_cluster.arn
}

output "eks_node_policy_arn" {
  description = "ARN of the EKS node managed IAM policy."
  value       = aws_iam_policy.eks_node.arn
}

output "eks_autoscaler_policy_arn" {
  description = "ARN of the EKS Cluster Autoscaler managed IAM policy."
  value       = aws_iam_policy.eks_autoscaler.arn
}

output "eks_load_balancer_policy_arn" {
  description = "ARN of the EKS load balancer controller managed IAM policy."
  value       = aws_iam_policy.eks_load_balancer.arn
}

output "ebs_csi_policy_arn" {
  description = "ARN of the EBS CSI driver managed IAM policy."
  value       = aws_iam_policy.ebs_csi.arn
}
