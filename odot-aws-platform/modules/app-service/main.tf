# modules/app-service/main.tf
#
# Shared locals and configuration for the app-service module.
# Individual resource files (ecr.tf, task-definition.tf, alb.tf, etc.)
# reference these locals for consistent tagging and naming.
#
# Requirements: 1.6, 11.5

locals {
  # Merge caller-supplied tags with module-level defaults so every resource
  # always carries the three mandatory tags (Environment, Project, Owner).
  default_tags = {
    Project = "ODOTWebHosting"
    Owner   = "odot-platform-team"
  }
}
