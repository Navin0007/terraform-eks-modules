# Skip in-place upgrade when the cluster is intended to stay on CONFIG_MAP (managed node groups + aws-auth).
resource "null_resource" "ensure_eks_authentication_mode" {
  count = coalesce(var.authentication_mode, "API_AND_CONFIG_MAP") != "CONFIG_MAP" ? 1 : 0
  triggers = {
    cluster_name = aws_eks_cluster.main.name
    region       = var.region
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/upgrade-eks-authentication-mode.sh"
    environment = {
      CLUSTER_NAME = aws_eks_cluster.main.name
      AWS_REGION   = var.region
    }
  }

  depends_on = [aws_eks_cluster.main]
}
