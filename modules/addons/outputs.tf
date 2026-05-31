output "coredns_arn" {
  description = "ARN of the CoreDNS EKS add-on."
  value       = aws_eks_addon.coredns.arn
}

output "coredns_version" {
  description = "Version of the CoreDNS add-on installed on the cluster."
  value       = aws_eks_addon.coredns.addon_version
}

output "ebs_csi_arn" {
  description = "ARN of the AWS EBS CSI driver EKS add-on."
  value       = aws_eks_addon.aws_ebs_csi_driver.arn
}

output "ebs_csi_version" {
  description = "Version of the AWS EBS CSI driver add-on installed on the cluster."
  value       = aws_eks_addon.aws_ebs_csi_driver.addon_version
}

output "addon_arns" {
  description = "Map of EKS add-on name to add-on ARN for post-node add-ons."
  value = {
    "coredns"            = aws_eks_addon.coredns.arn
    "aws-ebs-csi-driver" = aws_eks_addon.aws_ebs_csi_driver.arn
  }
}
