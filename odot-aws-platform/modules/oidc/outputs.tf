output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions via OIDC. Set this as the AWS_DEPLOY_ROLE_ARN variable in your GitHub repository or environment."
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role assumed by GitHub Actions via OIDC."
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider. Referenced by the IAM role trust policy."
  value       = aws_iam_openid_connect_provider.github.arn
}
