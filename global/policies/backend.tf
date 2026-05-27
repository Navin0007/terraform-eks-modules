# Remote state in the bootstrap S3 bucket. Pass bucket, region, kms_key_id, and
# use_lockfile=true via -backend-config on terraform init (from bootstrap outputs).
terraform {
  backend "s3" {
    key     = "global/policies/terraform.tfstate"
    encrypt = true
  }
}
