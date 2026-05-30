# provider.tf — AWS provider configuration for the internal-prod stack.
#
# When running locally with SSO profiles (e.g., AWS_PROFILE=odot-internal),
# set assume_role_arn to "" to authenticate directly.
#
# Requirements: 8.1

provider "aws" {
  region = "us-east-2"

  dynamic "assume_role" {
    for_each = var.assume_role_arn != "" ? [var.assume_role_arn] : []
    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = {
      Environment = "prod"
      Project     = "ODOTWebHosting"
      Owner       = "odot-platform-team"
    }
  }
}
