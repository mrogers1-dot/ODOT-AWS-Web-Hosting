# modules/security/variables.tf
#
# Input variable declarations for the security module.
# This module is consumed by all six account-stage stacks to provision
# account-wide security services: KMS, GuardDuty, Security Hub, Config, Macie.
#
# Requirements: 1.2, 1.3, 9.1, 9.2, 9.3, 9.4, 9.5

variable "account_type" {
  description = "Account type — 'internal' or 'external'. Used in resource names and SCP selection."
  type        = string

  validation {
    condition     = contains(["internal", "external"], var.account_type)
    error_message = "account_type must be 'internal' or 'external'."
  }
}

variable "account_id" {
  description = "AWS account ID where security resources are provisioned."
  type        = string
}

variable "org_id" {
  description = "AWS Organizations ID. Used for KMS key policy and SCP attachment."
  type        = string
}

variable "config_s3_bucket_name" {
  description = "Name of the S3 bucket used as the AWS Config delivery channel destination."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources. Must include Environment, Project, and Owner keys."
  type        = map(string)
  default     = {}
}
