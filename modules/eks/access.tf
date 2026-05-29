# EC2_LINUX access entry for the node IAM role (API authentication mode).
# Do not associate EKS cluster access policies here — AssociateAccessPolicy only
# works on STANDARD entries. Node AWS permissions come from IAM role attachments.
resource "aws_eks_access_entry" "node" {
  count = var.create_node_access_entry && var.enable_node_groups ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.node_role_arn
  type          = "EC2_LINUX"

  depends_on = [null_resource.ensure_eks_authentication_mode]
}
