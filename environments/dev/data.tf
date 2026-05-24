# Policy ARNs are owned by the global/policies root module (separate state).
# Do not embed global/policies here — CI applies that stack before dev.
data "terraform_remote_state" "policies" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "global/policies/terraform.tfstate"
    region = var.region
  }
}
