# modules/app-service/outputs.tf
#
# Output values for the app-service module. These are consumed by stack
# configurations and the odot-app-template Terraform to surface key
# resource identifiers after provisioning.
#
# Requirements: 4.1, 5.1, 7.3

output "ecr_repository_url" {
  description = "URL of the ECR repository for pushing container images. Used by CI/CD pipelines to tag and push Docker images."
  value       = aws_ecr_repository.app.repository_url
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer. Used to access the application or configure DNS records."
  value       = aws_lb.this.dns_name
}

output "ecs_service_name" {
  description = "Name of the ECS service. Used by CI/CD pipelines to trigger rolling deployments via aws ecs update-service."
  value       = aws_ecs_service.app.name
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition. Used for audit, rollback references, and CI/CD deployment tracking."
  value       = aws_ecs_task_definition.app.arn
}
