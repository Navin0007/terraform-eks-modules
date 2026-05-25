# EC2_LINUX access entries are for self-managed nodes only. Managed node groups use aws-auth.
resource "aws_eks_access_entry" "node" {
  count = var.create_node_access_entry ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.node_role_arn
  type          = "EC2_LINUX"

  depends_on = [null_resource.ensure_eks_authentication_mode]
}
