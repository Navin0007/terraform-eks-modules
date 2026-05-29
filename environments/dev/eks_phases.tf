# EKS phased provisioning: cluster → nodes → IRSA → add-ons.
# enable_eks=true enables all phases (backward compatible).

locals {
  eks_cluster_enabled = (
    var.enable_eks
    || var.enable_eks_cluster
    || var.enable_eks_nodes
    || var.enable_irsa
    || var.enable_addons
  )
  eks_nodes_enabled = var.enable_eks || var.enable_eks_nodes || var.enable_addons
  irsa_enabled      = var.enable_eks || var.enable_irsa || var.enable_addons
  addons_enabled    = var.enable_eks || var.enable_addons
}

check "eks_cluster_before_nodes" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_eks_nodes
      || var.enable_eks_cluster
    )
    error_message = "enable_eks_nodes requires enable_eks_cluster (or enable_eks=true for all phases)."
  }
}

check "eks_cluster_before_irsa" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_irsa
      || var.enable_eks_cluster
    )
    error_message = "enable_irsa requires enable_eks_cluster (or enable_eks=true)."
  }
}

check "eks_nodes_before_addons" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_addons
      || var.enable_eks_nodes
    )
    error_message = "enable_addons requires enable_eks_nodes (or enable_eks=true)."
  }
}

check "eks_irsa_before_addons" {
  assert {
    condition = (
      var.enable_eks
      || !var.enable_addons
      || var.enable_irsa
    )
    error_message = "enable_addons requires enable_irsa for the EBS CSI driver role (or enable_eks=true)."
  }
}
