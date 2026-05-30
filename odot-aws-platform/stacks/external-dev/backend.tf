# Backend configuration for the external-dev stack.
# State is stored in the External account (549136075921).

terraform {
  backend "s3" {
    bucket         = "odot-terraform-state-549136075921"
    key            = "external-dev/terraform.tfstate"
    region         = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
