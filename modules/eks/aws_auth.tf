# API_AND_CONFIG_MAP requires aws-auth mapRoles for managed node groups (in addition to access entries).
locals {
  node_role_map_entry = {
    rolearn  = var.node_role_arn
    username = "system:node:{{EC2PrivateDNSName}}"
    groups   = ["system:bootstrappers", "system:nodes"]
  }

  aws_auth_additional_map_roles = [
    for entry in var.aws_auth_map_roles : entry if entry.rolearn != var.node_role_arn
  ]

  aws_auth_merged_map_roles = concat(
    local.aws_auth_additional_map_roles,
    [local.node_role_map_entry],
  )

  aws_auth_map_roles_yaml = trimspace(yamlencode(local.aws_auth_merged_map_roles))
  aws_auth_map_users_yaml = trimspace(yamlencode(var.aws_auth_map_users))
}

resource "kubernetes_config_map_v1" "aws_auth" {
  provider = kubernetes
  count    = var.manage_aws_auth_configmap ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = local.aws_auth_map_roles_yaml
    mapUsers = local.aws_auth_map_users_yaml
  }

  depends_on = [
    aws_eks_cluster.main,
    null_resource.ensure_eks_authentication_mode,
  ]
}
