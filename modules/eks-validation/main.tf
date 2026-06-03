locals {
  skip_flags = {
    networking     = contains(split(",", var.skip_categories), "networking") ? "true" : "false"
    nodes          = contains(split(",", var.skip_categories), "nodes") ? "true" : "false"
    iam            = contains(split(",", var.skip_categories), "iam") ? "true" : "false"
    addons         = contains(split(",", var.skip_categories), "addons") ? "true" : "false"
    pod_networking = contains(split(",", var.skip_categories), "pod_networking") ? "true" : "false"
    storage        = contains(split(",", var.skip_categories), "storage") ? "true" : "false"
    logging        = contains(split(",", var.skip_categories), "logging") ? "true" : "false"
    security       = contains(split(",", var.skip_categories), "security") ? "true" : "false"
    tagging        = contains(split(",", var.skip_categories), "tagging") ? "true" : "false"
  }

  cloudwatch_log_group = coalesce(var.cloudwatch_log_group, "/aws/eks/${var.cluster_name}/cluster")
}

resource "null_resource" "post_apply_validation" {
  count = var.enabled ? 1 : 0

  triggers = {
    cluster_name        = var.cluster_name
    region              = var.region
    cluster_version     = coalesce(var.cluster_version, "")
    validation_triggers = var.validation_triggers
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/validate-eks-cluster.sh"
    environment = {
      CLUSTER_NAME               = var.cluster_name
      AWS_REGION                 = var.region
      EXPECTED_CLUSTER_NAME      = var.cluster_name
      EXPECTED_CLUSTER_VERSION   = coalesce(var.cluster_version, "")
      EXPECTED_VPC_ID            = coalesce(var.vpc_id, "")
      EXPECTED_VPC_CIDR          = coalesce(var.vpc_cidr, "")
      PRIVATE_SUBNET_IDS         = join(" ", var.private_subnet_ids)
      PUBLIC_SUBNET_IDS          = join(" ", var.public_subnet_ids)
      EXPECTED_CLUSTER_ROLE_ARN  = coalesce(var.cluster_role_arn, "")
      EXPECTED_NODE_ROLE_ARN     = coalesce(var.node_role_arn, "")
      EXPECTED_OIDC_PROVIDER_ARN = coalesce(var.oidc_provider_arn, "")
      CONTROL_PLANE_SG_ID        = coalesce(var.control_plane_sg_id, "")
      CLOUDWATCH_LOG_GROUP       = local.cloudwatch_log_group
      NODEGROUP_NAMES            = join(" ", var.nodegroup_names)
      EBS_CSI_ROLE_ARN           = coalesce(var.ebs_csi_role_arn, "")
      VALIDATE_POST_NODE_ADDONS  = var.validate_post_node_addons ? "true" : "false"
      VALIDATE_PVC_TEST          = var.validate_pvc_test ? "true" : "false"
      ALLOW_PUBLIC_WORLD_CIDR    = var.allow_public_world_cidr ? "true" : "false"
      SKIP_NETWORKING            = local.skip_flags.networking
      SKIP_NODES                 = local.skip_flags.nodes
      SKIP_IAM                   = local.skip_flags.iam
      SKIP_ADDONS                = local.skip_flags.addons
      SKIP_POD_NETWORKING        = local.skip_flags.pod_networking
      SKIP_STORAGE               = local.skip_flags.storage
      SKIP_LOGGING               = local.skip_flags.logging
      SKIP_SECURITY              = local.skip_flags.security
      SKIP_TAGGING               = local.skip_flags.tagging
    }
  }
}
