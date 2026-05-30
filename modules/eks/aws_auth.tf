# Managed node groups: EKS updates kube-system/aws-auth when the node group is created.
# Do not pre-merge aws-auth before aws_eks_node_group — it can block EKS wiring.
# CI repair scripts merge mapRoles only as a fallback (see prepare-managed-node-aws-auth.sh).
