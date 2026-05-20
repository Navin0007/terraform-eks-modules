output "coredns_id" {
  description = "ID of the CoreDNS EKS add-on."
  value       = aws_eks_addon.coredns.id
}

output "kube_proxy_id" {
  description = "ID of the kube-proxy EKS add-on."
  value       = aws_eks_addon.kube_proxy.id
}

output "vpc_cni_id" {
  description = "ID of the VPC CNI EKS add-on."
  value       = aws_eks_addon.vpc_cni.id
}

output "ebs_csi_id" {
  description = "ID of the aws-ebs-csi-driver EKS add-on."
  value       = aws_eks_addon.ebs_csi.id
}
