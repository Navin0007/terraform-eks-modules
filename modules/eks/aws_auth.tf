# Managed node groups in API_AND_CONFIG_MAP join via aws-auth mapRoles (remove stale CLI access entries in CI).
resource "null_resource" "aws_auth_node_role" {
  count = var.manage_aws_auth_configmap && var.enable_node_groups ? 1 : 0

  triggers = {
    cluster_name  = aws_eks_cluster.main.name
    node_role_arn = var.node_role_arn
    region        = var.region
    # Re-run when auth mode or role changes.
    auth_mode = coalesce(var.authentication_mode, "API_AND_CONFIG_MAP")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/ensure-node-cluster-auth.sh"
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
