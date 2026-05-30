# Managed node groups: EKS creates the EC2_LINUX access entry when the node group exists.
# Do not manage it in Terraform (pre-creating before the node group causes join failures).
#
# API_AND_CONFIG_MAP requires BOTH the EKS access entry and aws-auth mapRoles (see ensure-node-cluster-auth.sh).
