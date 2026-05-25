locals {
  eks_cluster_name = "${var.project_name}-${var.environment}-eks"
}

data "aws_eks_cluster" "auth" {
  name = local.eks_cluster_name
}

data "aws_eks_cluster_auth" "auth" {
  name = local.eks_cluster_name
}

provider "kubernetes" {
  alias                  = "eks"
  host                   = data.aws_eks_cluster.auth.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.auth.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.auth.token
}
