# Remote state in this module's S3 bucket (created by the resources below).
# CI swaps this file to backend "local" when the state bucket does not exist yet (see terraform-common.sh).
# Pass bucket, region, kms_key_id, and use_lockfile=true via -backend-config on init (see README).
terraform {
  backend "s3" {
    key     = "global/bootstrap/terraform.tfstate"
    encrypt = true
  }
}
