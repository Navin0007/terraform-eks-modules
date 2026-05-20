# Layer 1 — Terraform infrastructure baseline

Creates and manages the cluster and everything required for it to exist. Runs from **eks-platform** via **Terragrunt**.

## Components

| Area | Resources |
|------|-----------|
| **Compute** | EKS control plane, managed node groups |
| **Networking** | VPC, subnets, security groups |
| **Identity** | IAM roles and policies, OIDC provider |
| **Cluster add-ons** | CoreDNS, kube-proxy, VPC CNI |
| **Storage** | EBS CSI driver |
| **GitOps bootstrap** | ArgoCD (Helm install only) |

## Scope

This layer provisions the foundation: the EKS cluster, its networking and IAM, required add-ons, and a minimal ArgoCD install so higher layers can deploy workloads via GitOps.
