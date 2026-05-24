resource "aws_eks_access_entry" "node" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.node_role_arn
  type          = "EC2_LINUX"
}

resource "aws_eks_access_policy_association" "node" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.node.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodegroupPolicy"

  access_scope {
    type = "cluster"
  }
}
