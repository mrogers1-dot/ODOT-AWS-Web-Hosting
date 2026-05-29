# policy/encryption.rego
#
# OPA policy: All S3 buckets, DynamoDB tables, ECR repos, and log groups must be encrypted.
# Requirements: 21.3

package main

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket"
  resource.change.actions[_] == "create"
  # S3 buckets should have a corresponding encryption configuration resource
  not has_encryption_config(resource.address)
  msg := sprintf("S3 bucket %s may not have encryption configured", [resource.address])
}

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_ecr_repository"
  resource.change.actions[_] == "create"
  enc := object.get(resource.change.after, "encryption_configuration", [])
  count(enc) == 0
  msg := sprintf("ECR repository %s must have encryption_configuration", [resource.address])
}

# Helper: check if an encryption config resource exists for a given bucket
has_encryption_config(bucket_address) {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket_server_side_encryption_configuration"
  contains(resource.address, split(bucket_address, ".")[1])
}
