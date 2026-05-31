resource "aws_eks_addon" "coredns" {
  cluster_name = var.cluster_name
  addon_name   = "coredns"

  addon_version               = local.addon_versions.coredns
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  tags = local.common_tags

  timeouts {
    create = "45m"
    update = "45m"
  }

  depends_on = [
    terraform_data.cluster_dependency,
    data.aws_eks_cluster.main,
    terraform_data.nodes_ready,
    null_resource.ccm_initialized,
  ]
}
