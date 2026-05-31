resource "aws_launch_template" "node_group" {
  for_each = var.enable_node_groups ? var.node_groups : {}

  name_prefix = "${local.cluster_name}-${each.key}-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = each.value.disk_size_gb
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = var.kms_key_arn
    }
  }

  vpc_security_group_ids = [
    var.node_sg_id,
    aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
  ]

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name                                          = "${local.cluster_name}-${each.key}"
      "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.common_tags, {
      Name                                          = "${local.cluster_name}-${each.key}"
      "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}
