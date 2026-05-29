# terraform/variables.tf
#
# Input variables for the application Terraform configuration.
# Developers set these values in terraform.tfvars to onboard their application.
#
# Requirements: 7.2, 7.3, 7.6

# =============================================================================
# Application Configuration
# These are the primary variables developers must set for their application.
# =============================================================================

variable "app_name" {
  description = "Unique application identifier. Used in ECR repository names, log groups, IAM roles, and resource naming. Must be lowercase alphanumeric with hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-30 characters, lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "runtime" {
  description = "Container runtime platform. Use 'linux' for .NET Core, Node.js, Python, Java, or Go applications. Use 'windows' for .NET Framework/IIS applications."
  type        = string
  default     = "linux"

  validation {
    condition     = contains(["linux", "windows"], var.runtime)
    error_message = "runtime must be 'linux' or 'windows'."
  }
}

variable "container_port" {
  description = "Port the application container listens on. This is used for ALB target group health checks and ECS task port mappings."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "cpu" {
  description = "Fargate task CPU units. Valid values: 256, 512, 1024, 2048, 4096. Windows containers require minimum 1024."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "cpu must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "memory" {
  description = "Fargate task memory in MiB. Must be a valid value for the chosen CPU allocation. See AWS Fargate documentation for valid CPU/memory combinations."
  type        = number
  default     = 512
}

# =============================================================================
# Infrastructure Configuration
# These are provided by the platform team or looked up from the shared platform.
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources. ODOT platform uses us-east-2 (Ohio)."
  type        = string
  default     = "us-east-2"
}

variable "account_type" {
  description = "Account type — 'internal' for private/corporate apps, 'external' for public-facing apps."
  type        = string

  validation {
    condition     = contains(["internal", "external"], var.account_type)
    error_message = "account_type must be 'internal' or 'external'."
  }
}

variable "stage" {
  description = "Deployment stage — 'dev', 'test', or 'prod'. Controls log retention, capacity provider strategy, and resource naming."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.stage)
    error_message = "stage must be 'dev', 'test', or 'prod'."
  }
}

variable "vpc_id" {
  description = "VPC ID where the application resources are deployed. Provided by the platform team for each account-stage combination."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS task placement. Must span at least 2 Availability Zones."
  type        = list(string)
}

variable "alb_subnet_ids" {
  description = "List of subnet IDs for the ALB. Public subnets for external account, private subnets for internal account."
  type        = list(string)
}

variable "cluster_arn" {
  description = "ARN of the ECS Fargate cluster where the service will be deployed."
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster. Used to construct the auto-scaling resource ID."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt ECR images and CloudWatch logs."
  type        = string
}

variable "waf_acl_arn" {
  description = "ARN of the WAF Web ACL to associate with the ALB. Required for external account; set to empty string for internal."
  type        = string
  default     = ""
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarm notifications."
  type        = string
}

variable "owner" {
  description = "Owner tag value for resource tagging and cost allocation."
  type        = string
  default     = "odot-platform-team"
}
