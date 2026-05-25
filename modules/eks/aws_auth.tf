# API_AND_CONFIG_MAP still requires aws-auth mapRoles for managed node groups to join.
# See: https://repost.aws/questions/QUjHDhoRS_TiujGNIQ4FEECA/eks-access-entry-for-managed-nodes-existing-but-mng-nodes-cannot-join-the-eks-cluster
locals {
  aws_auth_additional_map_roles = [
    for entry in var.aws_auth_map_roles : entry if entry.rolearn != var.node_role_arn
  ]
  aws_auth_map_roles = concat(
    local.aws_auth_additional_map_roles,
    [
      {
        rolearn  = var.node_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
    ],
  )
}

resource "kubernetes_config_map_v1" "aws_auth" {
  provider = kubernetes
  count    = var.manage_aws_auth_configmap ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(local.aws_auth_map_roles)
    mapUsers = yamlencode(var.aws_auth_map_users)
  }

  depends_on = [
    aws_eks_cluster.main,
    null_resource.ensure_eks_authentication_mode,
  ]
}
