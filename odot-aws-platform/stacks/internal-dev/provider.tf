# provider.tf — AWS provider configuration for the internal-dev stack.
#
# When running locally with SSO profiles (e.g., AWS_PROFILE=odot-internal),
# set assume_role_arn to "" to authenticate directly.
# When running from CI/CD or a management account, provide the cross-account
# role ARN to assume into DOT-Web-Internal (577881328002).
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
      Environment = "dev"
      Project     = "ODOTWebHosting"
      Owner       = "odot-platform-team"
    }
  }
}
