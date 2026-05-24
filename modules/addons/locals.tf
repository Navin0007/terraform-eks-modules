locals {
  common_tags = merge(
    {
      project      = var.project_name
      environment  = var.environment
      cluster_name = var.cluster_name
      managed_by   = "terraform"
    },
    var.tags,
  )

  addon_versions = {
    coredns            = lookup(var.addon_versions, "coredns", null)
    vpc_cni            = lookup(var.addon_versions, "vpc-cni", null)
    kube_proxy         = lookup(var.addon_versions, "kube-proxy", null)
    aws_ebs_csi_driver = lookup(var.addon_versions, "aws-ebs-csi-driver", null)
  }
}
