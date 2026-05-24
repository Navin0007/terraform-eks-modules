resource "aws_eks_addon" "vpc_cni" {
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
