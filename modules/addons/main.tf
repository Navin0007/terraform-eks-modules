resource "terraform_data" "cluster_dependency" {
  input = var.cluster_id
}

data "aws_eks_cluster" "main" {
  name = var.cluster_name

  depends_on = [terraform_data.cluster_dependency]

  lifecycle {
    postcondition {
      condition     = self.status == "ACTIVE"
      error_message = "EKS cluster ${var.cluster_name} must be ACTIVE before installing add-ons."
    }
  }
}

# Stage 6 — post-node add-ons (CoreDNS, EBS CSI) after nodes are Ready and CCM-initialized.
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name = var.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  addon_version               = local.addon_versions.aws_ebs_csi_driver
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  service_account_role_arn    = var.ebs_csi_role_arn

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
