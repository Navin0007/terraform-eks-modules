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
  description = "Set after node group scale-out and Ready node verification (gates CCM wait and post-node add-ons)."
  value       = join(",", [for _, r in null_resource.node_group_scale_out : r.id])
}
