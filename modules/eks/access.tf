# EC2_LINUX access entry + AmazonEKSNodegroupPolicy for node IAM role (API authentication mode).
resource "aws_eks_access_entry" "node" {
  count = var.create_node_access_entry ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.node_role_arn
  type          = "EC2_LINUX"

  depends_on = [null_resource.ensure_eks_authentication_mode]
}

resource "aws_eks_access_policy_association" "node" {
  count = var.create_node_access_entry ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.node_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodegroupPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.node]
}
