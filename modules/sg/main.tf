locals {
  common_tags = merge(
    {
      project      = var.project_name
      environment  = var.environment
      managed_by   = "terraform"
      cluster_name = var.cluster_name
    },
    var.tags,
  )

  control_plane_sg_name = "${var.project_name}-${var.environment}-control-plane-sg"
  node_sg_name          = "${var.project_name}-${var.environment}-node-sg"
  bastion_sg_name       = "${var.project_name}-${var.environment}-bastion-sg"
  pod_sg_name           = "${var.project_name}-${var.environment}-pod-sg"

  additional_node_ingress = merge([
    for rule_key, rule in var.additional_node_ingress_rules : {
      for idx, cidr in rule.cidr_blocks :
      "${rule_key}-${idx}" => {
        from_port   = rule.from_port
        to_port     = rule.to_port
        protocol    = rule.protocol
        cidr        = cidr
        description = rule.description
      }
    }
  ]...)
}

resource "aws_security_group" "control_plane" {
  name        = local.control_plane_sg_name
  description = "EKS control plane for cluster ${var.cluster_name} in ${var.environment}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = local.control_plane_sg_name
  })
}

resource "aws_security_group" "node" {
  name        = local.node_sg_name
  description = "EKS worker nodes for cluster ${var.cluster_name} in ${var.environment}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = local.node_sg_name
  })
}

resource "aws_security_group" "bastion" {
  name        = local.bastion_sg_name
  description = "Bastion host for kubectl access to cluster ${var.cluster_name} in ${var.environment}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = local.bastion_sg_name
  })
}

resource "aws_security_group" "pod" {
  name        = local.pod_sg_name
  description = "Pod security group for Security Groups for Pods on cluster ${var.cluster_name}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = local.pod_sg_name
  })
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_from_nodes_443" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.node.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Kubelet to API server"
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_from_bastion_443" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "kubectl access from bastion"
}

resource "aws_vpc_security_group_egress_rule" "control_plane_to_nodes_kubelet" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.node.id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "API server to kubelet"
}

resource "aws_vpc_security_group_egress_rule" "control_plane_to_nodes_webhooks_443" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.node.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "API server webhooks to nodes"
}

resource "aws_vpc_security_group_ingress_rule" "node_from_control_plane_kubelet" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.control_plane.id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Kubelet and NodePort services from control plane"
}

resource "aws_vpc_security_group_ingress_rule" "node_from_control_plane_metrics_443" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.control_plane.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "API server to node metrics"
}

resource "aws_vpc_security_group_ingress_rule" "node_from_node_all" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
  description                  = "Node to node communication"
}

resource "aws_vpc_security_group_ingress_rule" "node_from_vpc_coredns_udp_53" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  description       = "CoreDNS UDP"
}

resource "aws_vpc_security_group_ingress_rule" "node_from_vpc_coredns_tcp_53" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  description       = "CoreDNS TCP"
}

resource "aws_vpc_security_group_ingress_rule" "node_additional" {
  for_each = local.additional_node_ingress

  security_group_id = aws_security_group.node.id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
  description       = each.value.description
}

resource "aws_vpc_security_group_egress_rule" "node_egress_all" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound for ECR, S3, and AWS APIs"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion_ingress_cidrs)

  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH access"
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_control_plane_443" {
  security_group_id            = aws_security_group.bastion.id
  referenced_security_group_id = aws_security_group.control_plane.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "kubectl to API server"
}

resource "aws_vpc_security_group_egress_rule" "bastion_https_443" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS outbound"
}

resource "aws_vpc_security_group_egress_rule" "bastion_http_80" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP outbound for package installs"
}

resource "aws_vpc_security_group_egress_rule" "pod_egress_all" {
  security_group_id = aws_security_group.pod.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Pod outbound traffic"
}
