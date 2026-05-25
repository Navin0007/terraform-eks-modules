# Launch template: disk + IMDS only (no custom SGs/AMI — EKS merges those and bootstrap user data).
resource "aws_launch_template" "node_group" {
  for_each = var.node_groups

  name_prefix = "${local.cluster_name}-${each.key}-"
  description = "EKS managed node group ${each.key}"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = each.value.disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.cluster_name}-${each.key}"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-${each.key}-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = each.value.ami_type
  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  launch_template {
    id      = aws_launch_template.node_group[each.key].id
    version = aws_launch_template.node_group[each.key].latest_version
  }

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-${each.key}"
  })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_access_entry.node,
    kubernetes_config_map_v1.aws_auth,
    aws_vpc_security_group_ingress_rule.control_plane_from_cluster_sg_https,
    aws_vpc_security_group_egress_rule.control_plane_to_cluster_sg_kubelet,
  ]
}
