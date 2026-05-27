# Root backend configuration — used for management-level resources.
# Replace MGMT_ACCOUNT_ID with the actual AWS management account ID
# (e.g., the account that owns the odot-terraform-state bucket).
# Run scripts/bootstrap-backend.sh once before the first `terraform init`.

terraform {
  backend "s3" {
    bucket         = "odot-terraform-state-MGMT_ACCOUNT_ID"
    key            = "management/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "odot-terraform-locks"
  }
}
