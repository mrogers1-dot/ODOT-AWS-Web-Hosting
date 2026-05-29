# modules/networking/variables.tf
#
# Input variable declarations for the networking module.
# This module is consumed by all six account-stage stacks.
#
# Requirements: 2.1, 2.3, 2.4, 3.1, 3.2

variable "account_type" {
  description = "Account type — 'internal' or 'external'. Controls whether public subnets, an internet gateway, and NAT gateways are created."
  type        = string

  validation {
    condition     = contains(["internal", "external"], var.account_type)
    error_message = "account_type must be 'internal' or 'external'."
  }
}

variable "stage" {
  description = "Deployment stage — 'dev', 'test', or 'prod'. Used in resource names and tags."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.stage)
    error_message = "stage must be 'dev', 'test', or 'prod'."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC (e.g., '10.0.0.0/16'). Must be large enough to accommodate all subnets."
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zone names to deploy subnets into (e.g., ['us-east-2a', 'us-east-2b']). Minimum 2 required for high availability."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "A minimum of 2 availability_zones must be provided for high availability."
  }
}

variable "tags" {
  description = "Tags to apply to all resources. Must include Environment, Project, and Owner keys."
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region for constructing VPC endpoint service names (e.g., 'us-east-2')."
  type        = string
  default     = "us-east-2"
}
