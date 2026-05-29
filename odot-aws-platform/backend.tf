# Root backend configuration — used for management-level resources.
# State is stored in the Internal account (577881328002).
# Run scripts/bootstrap-backend.sh 577881328002 once before the first `terraform init`.

terraform {
  backend "s3" {
    bucket         = "odot-terraform-state-577881328002"
    key            = "management/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "odot-terraform-locks"
  }
}
