# Remote state in this module's S3 bucket (created by the resources below).
# On first apply, init with -backend=false (local state), then migrate after the bucket exists.
# Pass bucket, region, kms_key_id, and dynamodb_table via -backend-config on init (see README).
terraform {
  backend "s3" {
    key     = "global/bootstrap/terraform.tfstate"
    encrypt = true
  }
}
