# versions.tf — Required provider versions for the internal-test stack.
#
# Pin the AWS provider to the 5.x major version to ensure compatibility
# with all modules while allowing minor/patch updates for bug fixes.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
