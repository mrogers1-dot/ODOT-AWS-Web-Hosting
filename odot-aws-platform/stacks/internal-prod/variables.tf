# variables.tf — Input variable declarations for the internal-prod stack.
#
# Simplified for shared-account testing — only networking and ECS variables.
# Account-level singletons are managed by the internal-dev stack.

# ── Provider ───────────────────────────────────────────────────────────────────

variable "assume_role_arn" {
  description = "ARN of the IAM role to assume. Empty string = use current credentials (SSO)."
  type        = string
  default     = ""
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the internal-prod VPC."
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zones for subnet placement (minimum 2)."
  type        = list(string)
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the ECS Fargate cluster (e.g., 'WebHosting-Prod')."
  type        = string
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all resources. Must include Environment, Project, and Owner."
  type        = map(string)
}
