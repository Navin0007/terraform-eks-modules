data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required", "opted-in"]
  }
}

check "azs_available" {
  assert {
    condition     = length(setsubtract(var.azs, data.aws_availability_zones.available.names)) == 0
    error_message = "Each value in var.azs must be an available zone in the configured AWS region."
  }
}
