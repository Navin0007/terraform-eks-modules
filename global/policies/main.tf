locals {
  name_prefix = "${var.project_name}-${var.environment}-"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    managed_by  = "terraform"
  }
}

data "aws_iam_policy_document" "eks_cluster" {
  statement {
    sid    = "EKSClusterAndControlPlaneLogs"
    effect = "Allow"

    actions = [
      "eks:Describe*",
      "eks:List*",
      "eks:AccessKubernetesApi",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "eks_cluster" {
  name        = "${local.name_prefix}eks-cluster"
  description = "EKS cluster control plane permissions for ${var.project_name} (${var.environment})"
  policy      = data.aws_iam_policy_document.eks_cluster.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}eks-cluster"
  })
}

data "aws_iam_policy_document" "eks_node" {
  statement {
    sid    = "EC2DescribeAndECRPull"
    effect = "Allow"

    actions = [
      "ec2:Describe*",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "eks_node" {
  name        = "${local.name_prefix}eks-node"
  description = "EKS worker node permissions for ${var.project_name} (${var.environment})"
  policy      = data.aws_iam_policy_document.eks_node.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}eks-node"
  })
}

data "aws_iam_policy_document" "eks_autoscaler" {
  statement {
    sid    = "ClusterAutoscaler"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "eks_autoscaler" {
  name        = "${local.name_prefix}eks-autoscaler"
  description = "Cluster Autoscaler permissions for ${var.project_name} (${var.environment})"
  policy      = data.aws_iam_policy_document.eks_autoscaler.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}eks-autoscaler"
  })
}

data "aws_iam_policy_document" "eks_load_balancer" {
  statement {
    sid    = "ElasticLoadBalancing"
    effect = "Allow"

    actions = [
      "elasticloadbalancing:*",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "EC2DescribeForLoadBalancers"
    effect = "Allow"

    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeClassicLinkInstances",
      "ec2:DescribeRouteTables",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "CreateELBServiceLinkedRole"
    effect = "Allow"

    actions = [
      "iam:CreateServiceLinkedRole",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "eks_load_balancer" {
  name        = "${local.name_prefix}eks-load-balancer"
  description = "AWS Load Balancer Controller permissions for ${var.project_name} (${var.environment})"
  policy      = data.aws_iam_policy_document.eks_load_balancer.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}eks-load-balancer"
  })
}

data "aws_iam_policy_document" "ebs_csi" {
  statement {
    sid    = "EBSVolumeLifecycle"
    effect = "Allow"

    actions = [
      "ec2:CreateSnapshot",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:ModifyVolume",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeSnapshots",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumesModifications",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "KMSForEncryptedVolumes"
    effect = "Allow"

    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
      "kms:Decrypt",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:DescribeKey",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "ebs_csi" {
  name        = "${local.name_prefix}ebs-csi"
  description = "EBS CSI driver permissions for ${var.project_name} (${var.environment})"
  policy      = data.aws_iam_policy_document.ebs_csi.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}ebs-csi"
  })
}
