# Layer 1 — Terraform infrastructure baseline

Creates and manages the cluster and everything required for it to exist. Runs from **eks-platform** via **Terragrunt**.

## Modules

| Module | Purpose |
|--------|---------|
| [eks-cluster](modules/eks-cluster) | Control plane, cluster IAM, OIDC, CloudWatch logs |
| [eks-node-group](modules/eks-node-group) | Managed node group, worker IAM, launch template |
| [eks-addons](modules/eks-addons) | CoreDNS, kube-proxy, VPC CNI, EBS CSI (pinned versions) |
| [eks-rbac](modules/eks-rbac) | `aws-auth` ConfigMap — IAM role to Kubernetes group mapping |

Apply in order: **cluster → node group → addons → rbac**.

## Components

| Area | Resources |
|------|-----------|
| **Compute** | EKS control plane, managed node groups |
| **Networking** | VPC, subnets, security groups |
| **Identity** | IAM roles and policies, OIDC provider |
| **Cluster add-ons** | CoreDNS, kube-proxy, VPC CNI |
| **Storage** | EBS CSI driver |

## Scope

This layer provisions the foundation: the EKS cluster, its networking and IAM, and required add-ons. Wire the Kubernetes provider for `eks-rbac` using `cluster_endpoint` and `cluster_ca_certificate` from `eks-cluster`.
