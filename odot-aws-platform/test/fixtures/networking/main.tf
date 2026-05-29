# Test fixture for modules/networking
#
# This fixture wraps the networking module with a mock AWS provider configuration
# that skips credential validation, allowing terraform plan to run without
# real AWS credentials. Used by Terratest for plan-based unit tests.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-2"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  # Use dummy credentials so the provider initializes without error.
  access_key = "mock-access-key"
  secret_key = "mock-secret-key"
}

module "networking" {
  source = "../../../modules/networking"

  account_type       = var.account_type
  stage              = var.stage
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = var.tags
}

variable "account_type" {
  type = string
}

variable "stage" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "vpc_cidr_block" {
  value = module.networking.vpc_cidr_block
}
