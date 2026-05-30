# terraform/main.tf
#
# Calls the app-service module from the odot-aws-platform repository to
# provision all per-application AWS resources: ECR repository, ECS service,
# ALB + target group, auto-scaling policies, CloudWatch alarms, and IAM roles.
#
# Requirements: 7.2, 7.3

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration — state stored in the external account.
  backend "s3" {
    bucket       = "odot-terraform-state-549136075921"
    key          = "apps/traffic-dash/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.stage
      Project     = "ODOTWebHosting"
      Owner       = var.owner
    }
  }
}

# -----------------------------------------------------------------------------
# App-Service Module
# Provisions ECR, ECS task definition, ECS service, ALB, auto-scaling, and
# CloudWatch alarms for this application.
# -----------------------------------------------------------------------------
module "app_service" {
  # Source from the platform repository.
  # TEMPORARY: Using personal GitHub (ftvizsla) for testing.
  # PRODUCTION: Change to "git::https://github.com/ODOT-GitHub-Org/odot-aws-platform.git//modules/app-service?ref=main"
  source = "git::https://github.com/ftvizsla/odot-aws-platform.git//modules/app-service?ref=main"

  # Application configuration
  app_name       = var.app_name
  runtime        = var.runtime
  container_port = var.container_port
  cpu            = var.cpu
  memory         = var.memory

  # Infrastructure references — provided by the platform team or looked up via data sources
  account_type       = var.account_type
  stage              = var.stage
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  alb_subnet_ids     = var.alb_subnet_ids
  cluster_arn        = var.cluster_arn
  cluster_name       = var.cluster_name
  kms_key_arn        = var.kms_key_arn
  waf_acl_arn        = var.waf_acl_arn
  sns_topic_arn      = var.sns_topic_arn

  tags = {
    Environment = var.stage
    Project     = "ODOTWebHosting"
    Owner       = var.owner
    Application = var.app_name
  }
}
