locals {
  bare_oidc_issuer_url = replace(var.cluster_oidc_issuer_url, "https://", "")

  # Use var.irsa_roles (not oidc_provider_arn) so for_each keys are known at plan time.
  # First IAM pass passes irsa_roles = {}; second pass passes roles after EKS creates OIDC.
  irsa_policy_attachments = length(var.irsa_roles) > 0 ? merge([
    for role_key, role in var.irsa_roles : {
      for policy_arn in role.policy_arns :
      "${role_key}/${policy_arn}" => {
        role_key   = role_key
        policy_arn = policy_arn
      }
    }
  ]...) : {}
}

data "aws_iam_policy_document" "irsa_trust" {
  for_each = var.irsa_roles

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.bare_oidc_issuer_url}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.bare_oidc_issuer_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = var.irsa_roles

  name               = "${var.project_name}-${var.environment}-${each.key}-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust[each.key].json

  tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
    irsa_role   = each.key
  }
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = local.irsa_policy_attachments

  role       = aws_iam_role.irsa[each.value.role_key].name
  policy_arn = each.value.policy_arn
}
