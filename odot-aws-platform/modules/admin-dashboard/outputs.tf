# modules/admin-dashboard/outputs.tf
#
# Output values for the admin-dashboard module. These are consumed by the
# dashboard application deployment (ECS task environment variables) and
# by the stack configurations.
#
# Requirements: 14.1, 14.29, 14.30

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool. Used by the dashboard backend for JWT validation."
  value       = aws_cognito_user_pool.dashboard.id
}

output "cognito_app_client_id" {
  description = "ID of the Cognito App Client. Used by the dashboard frontend for authentication flow."
  value       = aws_cognito_user_pool_client.dashboard.id
}

output "cognito_domain" {
  description = "Cognito hosted UI domain. Users are redirected here for Okta-federated login."
  value       = "${var.cognito_domain_prefix}.auth.us-east-2.amazoncognito.com"
}

output "audit_table_name" {
  description = "Name of the DynamoDB audit table. Used by the dashboard backend for logging actions."
  value       = aws_dynamodb_table.audit.name
}

output "audit_table_arn" {
  description = "ARN of the DynamoDB audit table. Used in IAM policy scoping."
  value       = aws_dynamodb_table.audit.arn
}

output "dashboard_task_role_arn" {
  description = "ARN of the dashboard ECS task IAM role. Attached to the dashboard task definition."
  value       = aws_iam_role.dashboard_task.arn
}

output "cross_account_role_arn" {
  description = "ARN of the cross-account role in the External account. The dashboard assumes this role for external resource management."
  value       = aws_iam_role.cross_account.arn
}

output "waf_ip_set_id" {
  description = "ID of the WAF IP set managed by the dashboard for IP blocking."
  value       = aws_wafv2_ip_set.dashboard_managed.id
}

output "waf_ip_set_arn" {
  description = "ARN of the WAF IP set managed by the dashboard."
  value       = aws_wafv2_ip_set.dashboard_managed.arn
}
