output "coredns_arn" {
  description = "ARN of the CoreDNS EKS add-on."
  value       = aws_eks_addon.coredns.arn
}

output "coredns_version" {
  description = "Version of the CoreDNS add-on installed on the cluster."
  value       = aws_eks_addon.coredns.addon_version
}

output "vpc_cni_arn" {
  description = "ARN of the Amazon VPC CNI EKS add-on."
  value       = var.install_vpc_cni_addon ? aws_eks_addon.vpc_cni[0].arn : data.aws_eks_addon.vpc_cni[0].arn
}

output "vpc_cni_version" {
  description = "Version of the Amazon VPC CNI add-on installed on the cluster."
  value       = var.install_vpc_cni_addon ? aws_eks_addon.vpc_cni[0].addon_version : data.aws_eks_addon.vpc_cni[0].addon_version
}

output "kube_proxy_arn" {
  description = "ARN of the kube-proxy EKS add-on."
  value       = aws_eks_addon.kube_proxy.arn
}

output "kube_proxy_version" {
  description = "Version of the kube-proxy add-on installed on the cluster."
  value       = aws_eks_addon.kube_proxy.addon_version
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
  description = "Map of EKS add-on name to add-on ARN for all managed add-ons."
  value = {
    "coredns"            = aws_eks_addon.coredns.arn
    "vpc-cni"            = var.install_vpc_cni_addon ? aws_eks_addon.vpc_cni[0].arn : data.aws_eks_addon.vpc_cni[0].arn
    "kube-proxy"         = aws_eks_addon.kube_proxy.arn
    "aws-ebs-csi-driver" = aws_eks_addon.aws_ebs_csi_driver.arn
  }
}
