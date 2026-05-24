locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"

  common_tags = merge(
    {
      Project      = var.project_name
      Environment  = var.environment
      cluster_name = local.cluster_name
      managed_by   = "terraform"
    },
    var.tags,
  )

  cloudwatch_log_group_name = "/aws/eks/${local.cluster_name}/cluster"
  fargate_enabled           = length(var.fargate_profiles) > 0
}
