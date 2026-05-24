locals {
  common_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      managed_by  = "terraform"
    },
    var.tags,
  )

}

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  count = var.create_core_roles ? 1 : 0

  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cluster"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_custom" {
  count = var.create_core_roles ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = var.eks_cluster_policy_arn
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  count = var.create_core_roles ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node" {
  count = var.create_core_roles ? 1 : 0

  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-node"
  })
}

resource "aws_iam_role_policy_attachment" "node_custom" {
  count = var.create_core_roles ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = var.eks_node_policy_arn
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  count = var.create_core_roles ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_read_only" {
  count = var.create_core_roles ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  count = var.create_core_roles ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

data "aws_iam_role" "cluster" {
  count = var.create_core_roles ? 0 : 1
  name  = "${var.cluster_name}-cluster"
}

data "aws_iam_role" "node" {
  count = var.create_core_roles ? 0 : 1
  name  = "${var.cluster_name}-node"
}
