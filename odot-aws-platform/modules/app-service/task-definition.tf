# modules/app-service/task-definition.tf
#
# Provisions an ECS Fargate task definition for the application.
#
# Key behaviors:
#   - Fargate-only: requires_compatibilities = ["FARGATE"], network_mode = "awsvpc"
#   - Linux runtime: read-only root filesystem, non-root user (UID 1000),
#     operatingSystemFamily = "LINUX" (Requirements 4.8, 9.8)
#   - Windows runtime: operatingSystemFamily = "WINDOWS_SERVER_2019_CORE",
#     cpuArchitecture = "X86_64". readonlyRootFilesystem and user are omitted
#     because Windows Fargate does not support these settings (platform limitation).
#   - CloudWatch Logs via awslogs driver at /ecs/{app_name}/{stage}
#
# Windows tasks require a minimum of 1024 CPU units (1 vCPU).
#
# Requirements: 4.7, 4.8, 9.8

locals {
  # Task definition family follows the naming convention: {app_name}-{stage}
  task_family = "${var.app_name}-${var.stage}"

  # CloudWatch log group path for ECS task logs
  log_group_name = "/ecs/${var.app_name}/${var.stage}"

  # Container definition for Linux runtime — includes security hardening
  linux_container_definition = {
    name  = var.app_name
    image = "${aws_ecr_repository.app.repository_url}:latest"

    portMappings = [
      {
        containerPort = var.container_port
        protocol      = "tcp"
      }
    ]

    # Security: read-only root filesystem prevents runtime file modification (Req 4.8, 9.8)
    readonlyRootFilesystem = true

    # Security: non-root user execution (Req 9.8)
    user = "1000"

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = local.log_group_name
        "awslogs-region"        = "us-east-2"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }

  # Container definition for Windows runtime — omits readonlyRootFilesystem and user
  # because Windows Fargate does not support these settings (platform limitation).
  windows_container_definition = {
    name  = var.app_name
    image = "${aws_ecr_repository.app.repository_url}:latest"

    portMappings = [
      {
        containerPort = var.container_port
        protocol      = "tcp"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = local.log_group_name
        "awslogs-region"        = "us-east-2"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }

  # Encode container definitions as JSON separately to avoid Terraform's
  # "inconsistent conditional result types" error — the Linux and Windows
  # objects have different attribute counts (Linux includes readonlyRootFilesystem
  # and user, Windows does not).
  container_definitions_json = var.runtime == "windows" ? jsonencode([local.windows_container_definition]) : jsonencode([local.linux_container_definition])
}

# ── ECS Task Definition ───────────────────────────────────────────────────────
#
# One task definition per application per stage. Fargate-only with awsvpc
# networking. The runtime_platform block configures the OS family and CPU
# architecture based on the runtime variable.
#
# Linux tasks enforce read-only root filesystem and non-root user execution.
# Windows tasks omit these settings due to platform limitations but still
# require minimum 1024 CPU units.
resource "aws_ecs_task_definition" "app" {
  family                   = local.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  # Runtime platform configuration differs by OS family.
  # Linux: operatingSystemFamily = "LINUX"
  # Windows: operatingSystemFamily = "WINDOWS_SERVER_2019_CORE", cpuArchitecture = "X86_64"
  runtime_platform {
    operating_system_family = var.runtime == "windows" ? "WINDOWS_SERVER_2019_CORE" : "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = local.container_definitions_json

  tags = merge(local.default_tags, var.tags, {
    Name = local.task_family
  })
}
