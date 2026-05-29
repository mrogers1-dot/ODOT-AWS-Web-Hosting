# modules/security/outputs.tf
#
# Outputs consumed by stack configurations and other modules (app-service,
# monitoring) that need the account CMK ARN or GuardDuty detector ID.
#
# Requirements: 1.2, 9.1, 9.5

output "kms_key_arn" {
  description = "ARN of the ODOT account Customer Managed Key. Pass to app-service and monitoring modules for ECR, log group, and SNS encryption."
  value       = aws_kms_key.this.arn
}

output "kms_key_id" {
  description = "Key ID of the ODOT account Customer Managed Key. Used when constructing key policy ARNs or referencing the key in IAM policies."
  value       = aws_kms_key.this.key_id
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector enabled in this account. Used for cross-account GuardDuty delegation and integration tests."
  value       = aws_guardduty_detector.this.id
}
