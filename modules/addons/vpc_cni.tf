# When install_vpc_cni_addon is false, the EKS module installs vpc-cni before node groups; this module only reads it for outputs/IRSA updates later.
resource "aws_eks_addon" "vpc_cni" {
  count = var.install_vpc_cni_addon ? 1 : 0

  cluster_name = var.cluster_name
  addon_name   = "vpc-cni"

  addon_version               = local.addon_versions.vpc_cni
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  service_account_role_arn    = var.vpc_cni_role_arn

  tags = local.common_tags

  depends_on = [
    terraform_data.cluster_dependency,
    data.aws_eks_cluster.main,
  ]
}

data "aws_eks_addon" "vpc_cni" {
  count = var.install_vpc_cni_addon ? 0 : 1

  cluster_name = var.cluster_name
  addon_name   = "vpc-cni"

  depends_on = [
    terraform_data.cluster_dependency,
    data.aws_eks_cluster.main,
  ]
}
