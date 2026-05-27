# Backend configuration for the external-test stack.
# Replace MGMT_ACCOUNT_ID with the actual management account ID before running
# `terraform init`. Run scripts/bootstrap-backend.sh first if the S3 bucket
# and DynamoDB table do not yet exist.

terraform {
  backend "s3" {
    bucket         = "odot-terraform-state-MGMT_ACCOUNT_ID"
    key            = "external-test/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "odot-terraform-locks"
  }
}
