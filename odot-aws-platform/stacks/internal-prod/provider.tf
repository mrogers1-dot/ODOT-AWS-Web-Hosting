# provider.tf — AWS provider configuration for the internal-prod stack.
#
# Configures the AWS provider to assume a cross-account role in the
# DOT-Web-Internal account (577881328002). This enables multi-account
# Terraform deployments from a central CI/CD runner or developer workstation.
#
# Requirements: 8.1

provider "aws" {
  region = "us-east-2"

  assume_role {
    role_arn = var.assume_role_arn
  }

  default_tags {
    tags = {
      Environment = "prod"
      Project     = "ODOTWebHosting"
      Owner       = "odot-platform-team"
    }
  }
}
