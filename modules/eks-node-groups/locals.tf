locals {
  common_tags = merge(
    {
      project      = var.project_name
      environment  = var.environment
      cluster_name = var.cluster_name
      managed_by   = "terraform"
    },
    var.tags,
  )
}

data "aws_eks_cluster" "main" {
  name = var.cluster_name
}
