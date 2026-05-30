locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"

  common_tags = merge(var.tags, {
    project     = var.project_name
    environment = var.environment
  })

  irsa_roles = merge(var.irsa_roles, {
    ebs-csi = merge(var.irsa_roles["ebs-csi"], {
      policy_arns = distinct(concat(
        [data.terraform_remote_state.policies.outputs.ebs_csi_policy_arn],
        var.irsa_roles["ebs-csi"].policy_arns
      ))
    })
  })
}

module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  region               = var.region
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  cluster_name         = local.cluster_name
  single_nat_gateway   = true
  tags                 = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  cluster_name   = local.cluster_name
  aws_account_id = var.aws_account_id
  region         = var.region

  eks_cluster_policy_arn       = data.terraform_remote_state.policies.outputs.eks_cluster_policy_arn
  eks_node_policy_arn          = data.terraform_remote_state.policies.outputs.eks_node_policy_arn
  eks_autoscaler_policy_arn    = data.terraform_remote_state.policies.outputs.eks_autoscaler_policy_arn
  eks_load_balancer_policy_arn = data.terraform_remote_state.policies.outputs.eks_load_balancer_policy_arn
  ebs_csi_policy_arn           = data.terraform_remote_state.policies.outputs.ebs_csi_policy_arn

  oidc_provider_arn       = ""
  cluster_oidc_issuer_url = ""
  irsa_roles              = {}

  tags = local.common_tags
}

module "sg" {
  source = "../../modules/sg"

  project_name         = var.project_name
  environment          = var.environment
  cluster_name         = local.cluster_name
  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = module.vpc.vpc_cidr_block
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  tags                 = local.common_tags

  depends_on = [module.vpc]
}

module "eks" {
  count  = local.eks_cluster_enabled ? 1 : 0
  source = "../../modules/eks"

  project_name    = var.project_name
  environment     = var.environment
  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version
  region          = var.region

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  cluster_role_arn = module.iam.cluster_role_arn
  node_role_arn    = module.iam.node_role_arn

  control_plane_sg_id = module.sg.control_plane_sg_id
  node_sg_id          = module.sg.node_sg_id

  kms_key_arn = var.state_kms_key_arn

  enable_node_groups = local.eks_nodes_enabled
  node_groups        = local.eks_nodes_enabled ? var.node_groups : {}

  # Managed nodes need API_AND_CONFIG_MAP with BOTH EKS access entry + aws-auth mapRoles.
  authentication_mode      = "API_AND_CONFIG_MAP"
  create_node_access_entry = false

  endpoint_private_access = true
  # Public endpoint required so CI/Terraform can apply the aws-auth ConfigMap (nodes still use the private endpoint).
  endpoint_public_access = true
  public_access_cidrs    = ["0.0.0.0/0"]

  tags = local.common_tags

  depends_on = [
    module.iam,
    module.sg,
  ]
}

module "iam_irsa" {
  count  = local.irsa_enabled && local.eks_cluster_enabled ? 1 : 0
  source = "../../modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  cluster_name   = local.cluster_name
  aws_account_id = var.aws_account_id
  region         = var.region

  eks_cluster_policy_arn       = data.terraform_remote_state.policies.outputs.eks_cluster_policy_arn
  eks_node_policy_arn          = data.terraform_remote_state.policies.outputs.eks_node_policy_arn
  eks_autoscaler_policy_arn    = data.terraform_remote_state.policies.outputs.eks_autoscaler_policy_arn
  eks_load_balancer_policy_arn = data.terraform_remote_state.policies.outputs.eks_load_balancer_policy_arn
  ebs_csi_policy_arn           = data.terraform_remote_state.policies.outputs.ebs_csi_policy_arn

  create_core_roles       = false
  oidc_provider_arn       = module.eks[0].oidc_provider_arn
  cluster_oidc_issuer_url = module.eks[0].cluster_oidc_issuer_url
  irsa_roles              = local.irsa_roles

  tags = local.common_tags

  depends_on = [module.eks]
}

module "addons" {
  count  = local.addons_enabled && local.eks_cluster_enabled && local.eks_nodes_enabled && local.irsa_enabled ? 1 : 0
  source = "../../modules/addons"

  project_name     = var.project_name
  environment      = var.environment
  cluster_name     = module.eks[0].cluster_name
  cluster_id       = module.eks[0].cluster_id
  cluster_version  = module.eks[0].cluster_version
  vpc_cni_role_arn = module.iam_irsa[0].irsa_role_arns["vpc-cni"]
  ebs_csi_role_arn = module.iam_irsa[0].irsa_role_arns["ebs-csi"]
  # vpc-cni is installed in module.eks before the node group joins.
  install_vpc_cni_addon  = false
  nodes_ready_dependency = module.eks[0].nodes_joined
  tags                   = local.common_tags

  depends_on = [
    module.iam_irsa,
    module.eks,
  ]
}
