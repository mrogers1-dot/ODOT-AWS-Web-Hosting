# Backend configuration for the internal-prod stack.
# State is stored in the Internal account (577881328002).

terraform {
  backend "s3" {
    bucket         = "odot-terraform-state-577881328002"
    key            = "internal-prod/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "odot-terraform-locks"
  }
}
