data "aws_iam_policy_document" "fargate_pod_execution_assume_role" {
  count = local.fargate_enabled ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "fargate_pod_execution" {
  count = local.fargate_enabled ? 1 : 0

  name               = "${local.cluster_name}-fargate-pod-execution"
  assume_role_policy = data.aws_iam_policy_document.fargate_pod_execution_assume_role[0].json

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-fargate-pod-execution"
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  count = local.fargate_enabled ? 1 : 0

  role       = aws_iam_role.fargate_pod_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_eks_fargate_profile" "main" {
  for_each = var.fargate_profiles

  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = each.key
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution[0].arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = each.value.namespace
    labels    = length(each.value.labels) > 0 ? each.value.labels : null
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-${each.key}-fargate"
  })

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.fargate_pod_execution,
  ]
}
