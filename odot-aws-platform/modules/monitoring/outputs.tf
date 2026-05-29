# modules/monitoring/outputs.tf
#
# Output values from the monitoring module.
# Requirements: 10.2, 10.4, 10.5, 11.1, 11.2

output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic. Used by app-service module for CloudWatch alarm notifications."
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for this account-stage combination."
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule capturing Security Hub Critical/High findings."
  value       = aws_cloudwatch_event_rule.securityhub_critical_high.arn
}
