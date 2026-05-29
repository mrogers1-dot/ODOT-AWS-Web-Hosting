# modules/ecs-cluster/outputs.tf
#
# Outputs consumed by stack configurations and other modules (app-service)
# that need to deploy services into this ECS cluster.
#
# Requirements: 4.1, 4.2, 11.3

output "cluster_arn" {
  description = "ARN of the ECS cluster. Used by app-service module to register ECS services."
  value       = aws_ecs_cluster.main.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster. Used for capacity provider references and CloudWatch metrics."
  value       = aws_ecs_cluster.main.name
}
