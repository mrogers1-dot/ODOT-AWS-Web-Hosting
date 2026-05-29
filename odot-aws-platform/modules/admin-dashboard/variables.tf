# modules/admin-dashboard/variables.tf
#
# Input variable declarations for the admin-dashboard module.
# This module provisions Cognito (Okta-federated), DynamoDB audit table,
# IAM roles for dashboard operations, and WAF IP set for managed blocking.
#
# Requirements: 14.1, 14.29, 14.30

variable "account_type" {
  description = "Account type — 'internal' or 'external'. The dashboard runs in the internal account but needs cross-account access to external."
  type        = string

  validation {
    condition     = contains(["internal", "external"], var.account_type)
    error_message = "account_type must be 'internal' or 'external'."
  }
}

variable "stage" {
  description = "Deployment stage — 'dev', 'test', or 'prod'."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.stage)
    error_message = "stage must be 'dev', 'test', or 'prod'."
  }
}

variable "internal_account_id" {
  description = "AWS account ID for the Internal account (where the dashboard runs)."
  type        = string
}

variable "external_account_id" {
  description = "AWS account ID for the External account (cross-account access target)."
  type        = string
}

variable "okta_issuer_url" {
  description = "Okta OIDC issuer URL (e.g., https://odot.okta.com/oauth2/default)."
  type        = string
}

variable "okta_client_id" {
  description = "Okta OIDC application client ID."
  type        = string
}

variable "okta_client_secret" {
  description = "Okta OIDC application client secret. Stored in Secrets Manager in production."
  type        = string
  sensitive   = true
}

variable "callback_urls" {
  description = "List of allowed callback URLs for Cognito hosted UI (e.g., ['https://dashboard.internal.odot.ohio.gov/callback'])."
  type        = list(string)
}

variable "logout_urls" {
  description = "List of allowed logout URLs for Cognito hosted UI."
  type        = list(string)
}

variable "cognito_domain_prefix" {
  description = "Cognito hosted UI domain prefix (e.g., 'odot-dashboard-dev'). Must be globally unique."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encrypting DynamoDB and SNS."
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic for audit event notifications."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources. Must include Environment, Project, and Owner keys."
  type        = map(string)
  default     = {}
}
