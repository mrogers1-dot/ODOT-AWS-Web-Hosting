# modules/ecs-cluster/variables.tf
#
# Input variable declarations for the ecs-cluster module.
# This module is consumed by all six account-stage stacks to provision one
# ECS Fargate cluster per account-stage combination.
#
# Requirements: 4.1, 4.2, 11.3

variable "cluster_name" {
  description = "Name of the ECS cluster (e.g., 'WebHosting-Prod'). Used as the cluster identifier and in resource naming."
  type        = string
}

variable "stage" {
  description = "Deployment stage — 'dev', 'test', or 'prod'. Controls the default capacity provider strategy: dev/test use FARGATE_SPOT, prod uses FARGATE."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.stage)
    error_message = "stage must be 'dev', 'test', or 'prod'."
  }
}

variable "tags" {
  description = "Tags to apply to all resources. Must include Environment, Project, and Owner keys."
  type        = map(string)
  default     = {}
}
