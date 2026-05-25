# Managed node groups in API_AND_CONFIG_MAP use aws-auth mapRoles (not EC2_LINUX access entries).
resource "null_resource" "aws_auth_node_role" {
  count = var.manage_aws_auth_configmap ? 1 : 0

  triggers = {
    cluster_name  = aws_eks_cluster.main.name
    node_role_arn = var.node_role_arn
    region        = var.region
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/apply-aws-auth-node-role.sh"
    environment = {
      CLUSTER_NAME  = aws_eks_cluster.main.name
      NODE_ROLE_ARN = var.node_role_arn
      AWS_REGION    = var.region
    }
  }

  depends_on = [
    aws_eks_cluster.main,
    null_resource.ensure_eks_authentication_mode,
  ]
}
