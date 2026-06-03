variable "project_name" {
  description = "Short project name used for resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region for all resources in this environment."
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "12-digit AWS account ID where this environment is deployed."
  type        = string
}

variable "enable_eks" {
  description = "When true, enables all EKS phases (cluster, nodes, IRSA, add-ons). Prefer phased flags for step-by-step applies."
  type        = bool
  default     = false
}

variable "enable_eks_cluster" {
  description = "Stage 3 — EKS control plane, OIDC provider, and CloudWatch logs."
  type        = bool
  default     = false
}

variable "enable_irsa" {
  description = "Stage 2 (identity) — IRSA roles for vpc-cni, kube-proxy, and ebs-csi (requires control plane/OIDC)."
  type        = bool
  default     = false
}

variable "enable_pre_node_addons" {
  description = "Stage 4 — vpc-cni (with IRSA) and kube-proxy add-ons before node groups (requires IRSA)."
  type        = bool
  default     = false
}

variable "enable_eks_nodes" {
  description = "Stage 5 — managed node groups, launch templates, and CCM initialization wait (requires pre-node add-ons)."
  type        = bool
  default     = false
}

variable "enable_addons" {
  description = "Stage 6 — post-node add-ons: CoreDNS, EBS CSI, and other workload add-ons (requires nodes)."
  type        = bool
  default     = false
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones for subnets and NAT gateways."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per availability zone."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per availability zone."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "node_groups" {
  description = "EKS managed node groups keyed by group name."
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size_gb   = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
    ami_type = string
  }))
  default = {
    app = {
      instance_types = ["t2.micro"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      disk_size_gb   = 20
      labels = {
        workload = "app"
      }
      taints   = []
      ami_type = "AL2_x86_64"
    }
    webapp = {
      instance_types = ["t2.micro"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      disk_size_gb   = 20
      labels = {
        workload = "webapp"
      }
      taints   = []
      ami_type = "AL2_x86_64"
    }
  }
}

variable "irsa_roles" {
  description = "IRSA roles created after the EKS OIDC provider exists (second IAM pass)."
  type = map(object({
    namespace       = string
    service_account = string
    policy_arns     = list(string)
  }))
  default = {
    vpc-cni = {
      namespace       = "kube-system"
      service_account = "aws-node"
      policy_arns     = ["arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"]
    }
    ebs-csi = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
      policy_arns     = []
    }
  }
}

variable "tags" {
  description = "Additional tags merged into all module resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    owner      = "platform-team"
  }
}

variable "state_bucket_name" {
  description = "S3 bucket name from global/bootstrap output. Used for the remote state backend and to read global/policies outputs."
  type        = string

  validation {
    condition     = var.state_bucket_name != ""
    error_message = "state_bucket_name is required (bootstrap output state_bucket_name / TF_STATE_BUCKET in CI)."
  }
}

variable "state_kms_key_id" {
  description = "KMS key ID from global/bootstrap output for state encryption. Documented for operators; backend.tf must be updated manually with this value."
  type        = string
  default     = ""
}

variable "dynamodb_table_name" {
  description = "DynamoDB lock table name from global/bootstrap output. Documented for operators; backend.tf must be updated manually with this value."
  type        = string
  default     = ""
}

variable "state_kms_key_arn" {
  description = "KMS key ARN from global/bootstrap output. Used for EKS secrets and node volume encryption."
  type        = string
}
