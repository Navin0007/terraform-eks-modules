output "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role."
  value       = var.create_core_roles ? aws_iam_role.cluster[0].arn : data.aws_iam_role.cluster[0].arn
}

output "cluster_role_name" {
  description = "Name of the EKS cluster IAM role."
  value       = var.create_core_roles ? aws_iam_role.cluster[0].name : data.aws_iam_role.cluster[0].name
}

output "node_role_arn" {
  description = "ARN of the EKS node IAM role."
  value       = var.create_core_roles ? aws_iam_role.node[0].arn : data.aws_iam_role.node[0].arn
}

output "node_role_name" {
  description = "Name of the EKS node IAM role."
  value       = var.create_core_roles ? aws_iam_role.node[0].name : data.aws_iam_role.node[0].name
}

output "irsa_role_arns" {
  description = "Map of IRSA role key to role ARN for every created IRSA role."
  value = {
    for key, role in aws_iam_role.irsa : key => role.arn
  }
}

output "irsa_role_names" {
  description = "Map of IRSA role key to role name for every created IRSA role."
  value = {
    for key, role in aws_iam_role.irsa : key => role.name
  }
}
