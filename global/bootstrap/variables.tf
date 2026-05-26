variable "project_name" {
  description = "Short name of the project used for resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example, dev, staging, prod)."
  type        = string
}

variable "region" {
  description = "AWS region where bootstrap resources are created."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID where bootstrap resources are provisioned."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "state_bucket_force_destroy" {
  description = "Allow Terraform to delete the state bucket even when it contains objects (use true only for teardown)."
  type        = bool
  default     = false
}
