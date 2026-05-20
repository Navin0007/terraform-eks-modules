variable "cluster_name" {
  description = "Name of the EKS cluster to install add-ons into."
  type        = string
}

variable "coredns_version" {
  description = "Version of the CoreDNS EKS add-on."
  type        = string
}

variable "kube_proxy_version" {
  description = "Version of the kube-proxy EKS add-on."
  type        = string
}

variable "vpc_cni_version" {
  description = "Version of the VPC CNI EKS add-on."
  type        = string
}

variable "ebs_csi_version" {
  description = "Version of the aws-ebs-csi-driver EKS add-on."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
