# Remote state backend (S3 + lockfile + KMS).
#
# Backend arguments cannot use Terraform variables. For local applies, copy bootstrap
# outputs into -backend-config files or pass -backend-config flags on init (see
# README). CI supplies these via bootstrap outputs after apply.
#
#   bucket         <- state_bucket_name
#   kms_key_id     <- kms_key_id
#   use_lockfile   <- true
#   region         <- same as var.region
terraform {
  backend "s3" {
    key     = "dev/terraform.tfstate"
    encrypt = true
  }
}
