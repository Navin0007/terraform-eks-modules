# Post-apply EKS validation — runs kubectl/aws checks after the stack is fully wired.
# CI also runs the same script via run_eks_post_apply_validation in terraform-common.sh.

locals {
  eks_validation_enabled = (
    local.eks_control_plane_enabled
    && local.eks_nodes_enabled
    && local.pre_node_addons_enabled
  )

  eks_validation_triggers = join(",", compact([
    local.eks_control_plane_enabled ? module.eks[0].cluster_id : "",
    local.pre_node_addons_enabled ? local.pre_node_addons_dependency : "",
    local.eks_nodes_enabled && local.eks_control_plane_enabled ? module.eks_node_groups[0].nodes_joined : "",
    local.post_node_addons_enabled && local.eks_control_plane_enabled ? join(",", values(module.addons[0].addon_arns)) : "",
  ]))
}

module "eks_validation" {
  count  = local.eks_validation_enabled ? 1 : 0
  source = "../../modules/eks-validation"

  cluster_name = module.eks[0].cluster_name
  region       = var.region

  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  cluster_role_arn     = module.iam.cluster_role_arn
  node_role_arn        = module.iam.node_role_arn
  oidc_provider_arn    = module.eks[0].oidc_provider_arn
  control_plane_sg_id  = module.sg.control_plane_sg_id
  cloudwatch_log_group = module.eks[0].cloudwatch_log_group_name

  nodegroup_names = keys(var.node_groups)

  ebs_csi_role_arn = (
    local.post_node_addons_enabled && local.irsa_enabled && local.eks_control_plane_enabled
    ? module.iam_irsa[0].irsa_role_arns["ebs-csi"]
    : null
  )

  validate_post_node_addons = local.post_node_addons_enabled
  allow_public_world_cidr   = true
  validation_triggers       = local.eks_validation_triggers

  depends_on = [
    module.eks[0],
    module.eks_node_groups[0],
    aws_eks_addon.vpc_cni[0],
    aws_eks_addon.kube_proxy[0],
    module.addons,
  ]
}
