resource "aws_eks_node_group" "main" {
  for_each = var.enable_node_groups ? var.node_groups : {}

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = each.value.ami_type
  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types
  disk_size      = each.value.disk_size_gb

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
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

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_addon.vpc_cni,
    null_resource.aws_auth_node_role[0],
  ]
}

resource "null_resource" "node_group_scale_out" {
  for_each = var.manage_aws_auth_configmap && var.enable_node_groups ? var.node_groups : {}

  triggers = {
    node_group_id = aws_eks_node_group.main[each.key].id
    desired_size  = each.value.desired_size
    node_role_arn = var.node_role_arn
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/wait-for-ready-nodes.sh"
    environment = {
      CLUSTER_NAME   = aws_eks_cluster.main.name
      NODEGROUP_NAME = each.key
      NODE_ROLE_ARN  = var.node_role_arn
      AWS_REGION     = var.region
      DESIRED_SIZE   = each.value.desired_size
    }
  }

  depends_on = [aws_eks_node_group.main]
}
