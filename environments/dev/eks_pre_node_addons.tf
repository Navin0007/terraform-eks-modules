# Stage 4 — pre-node add-ons (vpc-cni with IRSA, kube-proxy) before managed node groups join.
resource "aws_eks_addon" "vpc_cni" {
  count = local.pre_node_addons_enabled && local.eks_control_plane_enabled && local.irsa_enabled ? 1 : 0

  cluster_name = module.eks[0].cluster_name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = module.iam_irsa[0].irsa_role_arns["vpc-cni"]

  depends_on = [
    module.eks,
    module.iam_irsa,
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  count = local.pre_node_addons_enabled && local.eks_control_plane_enabled && local.irsa_enabled ? 1 : 0

  cluster_name = module.eks[0].cluster_name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  timeouts {
    create = "45m"
    update = "45m"
  }

  depends_on = [
    module.eks,
    module.iam_irsa,
    aws_eks_addon.vpc_cni,
  ]
}

locals {
  pre_node_addons_dependency = (
    local.pre_node_addons_enabled && local.eks_control_plane_enabled && local.irsa_enabled
    ? join(",", [aws_eks_addon.vpc_cni[0].arn, aws_eks_addon.kube_proxy[0].arn])
    : ""
  )
}
