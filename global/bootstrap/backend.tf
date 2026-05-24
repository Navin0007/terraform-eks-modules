# Uses a local backend on first apply. After the state bucket exists, migrate with:
#
#   terraform init -migrate-state \
#     -backend-config="bucket=<state_bucket_name>" \
#     -backend-config="key=global/bootstrap/terraform.tfstate" \
#     -backend-config="region=<region>" \
#     -backend-config="kms_key_id=<kms_key_id>" \
#     -backend-config="dynamodb_table=<dynamodb_table_name>" \
#     -backend-config="encrypt=true"
#
# GitHub Actions performs this migration automatically after the first bootstrap apply.
terraform {
  backend "local" {}
}
