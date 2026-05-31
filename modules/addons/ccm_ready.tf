# Stage 6 gate — wait for CCM to clear the uninitialized taint and set topology labels.
resource "null_resource" "ccm_initialized" {
  provisioner "local-exec" {
    command = "bash ${path.module}/../eks/scripts/wait-for-ready-nodes.sh"
    environment = {
      CLUSTER_NAME      = var.cluster_name
      NODE_ROLE_ARN     = var.node_role_arn
      AWS_REGION        = var.region
      NODEGROUP_NAME    = var.nodegroup_name
      DESIRED_SIZE      = tostring(var.node_desired_size)
      REQUIRE_CCM_INIT  = "true"
      MAX_WAIT_ATTEMPTS = "90"
    }
  }

  depends_on = [terraform_data.nodes_ready]
}
