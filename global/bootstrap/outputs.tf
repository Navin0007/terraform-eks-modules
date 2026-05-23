output "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform remote state."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket used for Terraform remote state."
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.terraform_state_lock.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Terraform state and lock table data."
  value       = aws_kms_key.terraform_state.arn
}

output "kms_key_id" {
  description = "ID of the KMS key used to encrypt Terraform state and lock table data."
  value       = aws_kms_key.terraform_state.key_id
}
