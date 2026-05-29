# variables.tf — Input variable declarations for the internal-dev stack.
#
# These variables are populated via terraform.tfvars and allow the stack
# to be configured without modifying HCL source files.
#
# Requirements: 1.1, 8.3

# ── Provider ───────────────────────────────────────────────────────────────────

variable "assume_role_arn" {
  description = "ARN of the IAM role to assume for cross-account access to DOT-Web-Internal."
  type        = string
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the internal-dev VPC."
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zones for subnet placement (minimum 2)."
  type        = list(string)
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the ECS Fargate cluster (e.g., 'WebHosting-Dev')."
  type        = string
}

# ── Security ──────────────────────────────────────────────────────────────────

variable "account_id" {
  description = "AWS account ID for the Internal account (DOT-Web-Internal)."
  type        = string
}

variable "org_id" {
  description = "AWS Organizations ID for SCP and KMS key policy scoping."
  type        = string
}

variable "config_s3_bucket_name" {
  description = "S3 bucket name for AWS Config delivery channel."
  type        = string
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "slack_workspace_id" {
  description = "Slack workspace ID for AWS Chatbot integration."
  type        = string
}

variable "slack_channel_id" {
  description = "Slack channel ID for the #aws-alerts-internal channel."
  type        = string
}

variable "alert_email" {
  description = "Email address for alarm notifications (ServiceNow/FortiSIEM)."
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly budget limit in USD for this account."
  type        = number
  default     = 1000
}

# ── OIDC ──────────────────────────────────────────────────────────────────────

variable "github_org" {
  description = "GitHub Enterprise organization name."
  type        = string
}

variable "github_repos" {
  description = "List of GitHub repository names allowed to assume the deploy role."
  type        = list(string)
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all resources. Must include Environment, Project, and Owner."
  type        = map(string)
}
