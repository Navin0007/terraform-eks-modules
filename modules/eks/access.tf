# EC2_LINUX access entry plus aws-auth mapRoles (see aws_auth.tf) are both required for API_AND_CONFIG_MAP.
resource "aws_eks_access_entry" "node" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.node_role_arn
  type          = "EC2_LINUX"

  depends_on = [null_resource.ensure_eks_authentication_mode]
}
