# Allow the EKS-managed cluster SG (on nodes and API ENIs) to reach the custom control plane SG.
locals {
  cluster_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_from_cluster_sg_https" {
  security_group_id            = var.control_plane_sg_id
  referenced_security_group_id = local.cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Cluster SG to Kubernetes API"
}

resource "aws_vpc_security_group_egress_rule" "control_plane_to_cluster_sg_kubelet" {
  security_group_id            = var.control_plane_sg_id
  referenced_security_group_id = local.cluster_security_group_id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Kubernetes API to nodes (kubelet)"
}

resource "aws_vpc_security_group_egress_rule" "control_plane_to_cluster_sg_webhooks" {
  security_group_id            = var.control_plane_sg_id
  referenced_security_group_id = local.cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Kubernetes API webhooks to nodes"
}
