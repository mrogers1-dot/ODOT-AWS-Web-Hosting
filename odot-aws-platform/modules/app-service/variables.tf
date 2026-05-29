# modules/app-service/variables.tf
#
# Input variable declarations for the app-service module.
# This module provisions all per-application resources: ECR repo, ECS task
# definition, ECS service, ALB + target group, auto-scaling policies,
# CloudWatch alarms, and IAM roles.
#
# Requirements: 4.1, 5.1, 7.3

variable "app_name" {
  description = "Application identifier used in resource naming (e.g., 'myapp'). Forms part of the ECR repository name, log group path, and IAM role names."
  type        = string
}

variable "account_type" {
  description = "Account type — 'internal' or 'external'. Controls ALB scheme, WAF association, and ECR repository naming."
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

variable "kms_key_arn" {
  description = "ARN of the KMS customer-managed key used to encrypt ECR images and CloudWatch logs."
  type        = string
}

variable "runtime" {
  description = "Container runtime platform — 'linux' or 'windows'. Controls task definition runtime_platform, security settings, and capacity provider strategy."
  type        = string

  validation {
    condition     = contains(["linux", "windows"], var.runtime)
    error_message = "runtime must be 'linux' or 'windows'."
  }
}

variable "container_port" {
  description = "Port the container listens on. Used in task definition port mappings and ALB target group health checks."
  type        = number
}

variable "cpu" {
  description = "Task CPU units (256–4096 for Linux; minimum 1024 for Windows). Maps to Fargate vCPU allocation."
  type        = number
}

variable "memory" {
  description = "Task memory in MiB. Must be a valid Fargate memory value for the chosen CPU allocation."
  type        = number
}

variable "vpc_id" {
  description = "VPC ID where security groups and target groups are created."
  type        = string
}

variable "alb_subnet_ids" {
  description = "Subnet IDs for the ALB. Public subnets for external account, private subnets for internal account."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where ECS tasks are placed (awsvpc networking)."
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the ECS cluster where the service runs. Used to construct the auto-scaling resource ID (service/{cluster_name}/{service_name})."
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the target ECS cluster where the service is deployed. Used in the aws_ecs_service resource."
  type        = string
}

variable "waf_acl_arn" {
  description = "ARN of the WAF Web ACL to associate with the ALB. Required for external account; set to empty string for internal account."
  type        = string
  default     = ""
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarm notifications. Alarms publish to this topic when transitioning to ALARM or OK state."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources. Must include Environment, Project, and Owner keys."
  type        = map(string)
  default     = {}
}

# ── TLS & DNS Variables (Requirement 16) ──────────────────────────────────────

variable "domain_name" {
  description = "Fully qualified domain name for the application (e.g., 'myapp.dev.odot.ohio.gov'). Set to empty string to skip Route 53 record creation."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for the application's domain. Required when domain_name is set."
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS. Must be a validated certificate covering the domain_name."
  type        = string
  default     = ""
}
