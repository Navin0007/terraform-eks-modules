variable "project_name" {
  description = "Short name of the project used for resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example, dev, staging, prod)."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID where managed policies are provisioned."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region used by the AWS provider."
  type        = string
}
