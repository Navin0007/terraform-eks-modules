# State migration after restructuring provisioning stages.

moved {
  from = module.eks[0].aws_eks_addon.vpc_cni
  to   = aws_eks_addon.vpc_cni[0]
}

moved {
  from = module.eks[0].aws_eks_addon.vpc_cni[0]
  to   = aws_eks_addon.vpc_cni[0]
}

moved {
  from = module.addons[0].aws_eks_addon.kube_proxy
  to   = aws_eks_addon.kube_proxy[0]
}

moved {
  from = module.eks[0].aws_eks_addon.kube_proxy[0]
  to   = aws_eks_addon.kube_proxy[0]
}

moved {
  from = module.eks[0].aws_eks_node_group.main["general"]
  to   = module.eks_node_groups[0].aws_eks_node_group.main["general"]
}

moved {
  from = module.eks[0].aws_launch_template.node_group["general"]
  to   = module.eks_node_groups[0].aws_launch_template.node_group["general"]
}

moved {
  from = module.eks[0].null_resource.node_group_scale_out["general"]
  to   = module.eks_node_groups[0].null_resource.node_group_scale_out["general"]
}
