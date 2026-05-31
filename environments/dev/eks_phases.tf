# EKS staged provisioning (6 stages):
#   1 foundation  — VPC, subnets, security groups (always on)
#   2 identity    — cluster/node IAM roles, OIDC provider, IRSA (vpc-cni, kube-proxy, ebs-csi)
#   3 control_plane — EKS cluster, CloudWatch logs
#   4 pre_node_addons — vpc-cni (IRSA), kube-proxy
#   5 nodes       — launch template, node group, CCM wait
#   6 post_node_addons — CoreDNS, EBS CSI, other workload add-ons
#
# enable_eks=true enables all stages (backward compatible).

locals {
  eks_control_plane_enabled = (
    var.enable_eks
    || var.enable_eks_cluster
    || var.enable_irsa
    || var.enable_pre_node_addons
    || var.enable_eks_nodes
    || var.enable_addons
  )
  irsa_enabled = (
    var.enable_eks
    || var.enable_irsa
    || var.enable_pre_node_addons
    || var.enable_addons
  )
  pre_node_addons_enabled = (
    var.enable_eks
    || var.enable_pre_node_addons
    || var.enable_eks_nodes
    || var.enable_addons
  )
  eks_nodes_enabled = (
    var.enable_eks
    || var.enable_eks_nodes
    || var.enable_addons
  )
  post_node_addons_enabled = var.enable_eks || var.enable_addons
}

check "control_plane_before_irsa" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_irsa
      || var.enable_eks_cluster
    )
    error_message = "enable_irsa requires enable_eks_cluster (or enable_eks=true)."
  }
}

check "irsa_before_pre_node_addons" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_pre_node_addons
      || var.enable_irsa
    )
    error_message = "enable_pre_node_addons requires enable_irsa for vpc-cni IRSA (or enable_eks=true)."
  }
}

check "pre_node_addons_before_nodes" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_eks_nodes
      || var.enable_pre_node_addons
    )
    error_message = "enable_eks_nodes requires enable_pre_node_addons (or enable_eks=true)."
  }
}

check "control_plane_before_pre_node_addons" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_pre_node_addons
      || var.enable_eks_cluster
    )
    error_message = "enable_pre_node_addons requires enable_eks_cluster (or enable_eks=true)."
  }
}

check "control_plane_before_nodes" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_eks_nodes
      || var.enable_eks_cluster
    )
    error_message = "enable_eks_nodes requires enable_eks_cluster (or enable_eks=true)."
  }
}

check "nodes_before_post_node_addons" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_addons
      || var.enable_eks_nodes
    )
    error_message = "enable_addons requires enable_eks_nodes (or enable_eks=true)."
  }
}

check "irsa_before_post_node_addons" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_addons
      || var.enable_irsa
    )
    error_message = "enable_addons requires enable_irsa for the EBS CSI driver role (or enable_eks=true)."
  }
}
