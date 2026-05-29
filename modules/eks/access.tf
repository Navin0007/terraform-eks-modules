# Managed node groups in API mode: EKS creates the EC2_LINUX access entry when the
# node group is created. Do not manage it in Terraform (pre-creating causes Unauthorized).
#
# For API_AND_CONFIG_MAP, use aws-auth via null_resource.aws_auth_node_role instead.
