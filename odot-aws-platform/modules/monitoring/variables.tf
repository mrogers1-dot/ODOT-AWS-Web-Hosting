# modules/monitoring/variables.tf
#
# Input variable declarations for the monitoring module.
# This module provisions CloudWatch dashboards, SNS topics, AWS Chatbot
# Slack integrations, EventBridge rules, and AWS Budgets.
#
# Requirements: 9.9, 10.2, 10.4, 10.5, 11.1, 11.2

variable "account_type" {
  description = "Account type — 'internal' or 'external'. Controls SNS topic naming and Slack channel routing."
  type        = string

  validation {
    condition     = contains(["internal", "external"], var.account_type)
    error_message = "account_type must be 'internal' or 'external'."
  }
}

variable "stage" {
  description = "Deployment stage — 'dev', 'test', or 'prod'. Controls dashboard naming and budget configuration."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.stage)
    error_message = "stage must be 'dev', 'test', or 'prod'."
  }
}

variable "slack_workspace_id" {
  description = "Slack workspace ID for AWS Chatbot integration."
  type        = string
}

variable "slack_channel_id" {
  description = "Slack channel ID for alert notifications. Internal account uses #aws-alerts-internal, external uses #aws-alerts-external."
  type        = string
}

variable "alert_email" {
  description = "Email address for alarm notifications (consumed by ServiceNow or FortiSIEM)."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS customer-managed key used to encrypt the SNS topic at rest."
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly budget limit in USD. Notification fires at 80% of this value."
  type        = number
  default     = 1000
}

variable "tags" {
  description = "Tags to apply to all resources. Must include Environment, Project, and Owner keys."
  type        = map(string)
  default     = {}
}
