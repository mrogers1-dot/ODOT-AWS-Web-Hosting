# modules/resilience/outputs.tf

output "fis_stop_tasks_template_id" {
  description = "ID of the FIS experiment template for stopping tasks in a single AZ."
  value       = aws_fis_experiment_template.stop_tasks_single_az.id
}

output "fis_bad_deployment_template_id" {
  description = "ID of the FIS experiment template for circuit breaker validation."
  value       = aws_fis_experiment_template.bad_deployment.id
}
