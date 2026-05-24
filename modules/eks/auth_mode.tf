# CONFIG_MAP clusters cannot use aws_eks_access_entry until authentication mode is upgraded in-place.
resource "null_resource" "ensure_eks_authentication_mode" {
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
