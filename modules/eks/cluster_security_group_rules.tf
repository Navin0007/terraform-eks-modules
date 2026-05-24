# Custom node SGs in the launch template disable EKS auto-wiring; add required cluster SG rules.
# https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html#launch-template-custom-security-groups

locals {
  cluster_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "cluster_sg_from_node_sg_https" {
  security_group_id            = local.cluster_security_group_id
  referenced_security_group_id = var.node_sg_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Nodes to cluster API"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_sg_from_node_sg_kubelet" {
  security_group_id            = local.cluster_security_group_id
  referenced_security_group_id = var.node_sg_id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Nodes kubelet and NodePort from cluster"
}

resource "aws_vpc_security_group_egress_rule" "cluster_sg_to_node_sg_https" {
  security_group_id            = local.cluster_security_group_id
  referenced_security_group_id = var.node_sg_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Cluster API to nodes"
}

resource "aws_vpc_security_group_egress_rule" "cluster_sg_to_node_sg_kubelet" {
  security_group_id            = local.cluster_security_group_id
  referenced_security_group_id = var.node_sg_id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Cluster to node kubelet"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_sg_from_control_plane_sg_https" {
  security_group_id            = local.cluster_security_group_id
  referenced_security_group_id = var.control_plane_sg_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Control plane SG to cluster SG"
}

resource "aws_vpc_security_group_ingress_rule" "node_sg_from_cluster_sg" {
  security_group_id            = var.node_sg_id
  referenced_security_group_id = local.cluster_security_group_id
  ip_protocol                  = "-1"
  description                  = "Cluster SG to worker nodes"
}

resource "aws_vpc_security_group_egress_rule" "node_sg_to_cluster_sg_https" {
  security_group_id            = var.node_sg_id
  referenced_security_group_id = local.cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Nodes to cluster API"
}
