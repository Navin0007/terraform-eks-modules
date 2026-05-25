# API_AND_CONFIG_MAP: kubelet auth uses aws-auth mapRoles (Unauthorized without this entry).
locals {
  aws_auth_map_roles = <<-YAML
    - rolearn: ${var.node_role_arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
  YAML
}

resource "kubernetes_config_map_v1" "aws_auth" {
  provider = kubernetes
  count    = var.manage_aws_auth_configmap ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = trimspace(local.aws_auth_map_roles)
  }

  depends_on = [
    aws_eks_cluster.main,
    null_resource.ensure_eks_authentication_mode,
  ]
}
