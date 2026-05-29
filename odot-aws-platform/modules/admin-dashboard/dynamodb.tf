# modules/admin-dashboard/dynamodb.tf
#
# Provisions the DynamoDB audit table for the admin dashboard.
# All mutating actions (restart, stop, scale, rollback, block IP, etc.)
# are logged here with the user, action, target, and timestamp.
#
# Table design:
#   - Partition key (pk): app#stage (e.g., "myapp#prod")
#   - Sort key (sk): timestamp (ISO 8601, e.g., "2024-01-15T10:30:00Z")
#   - GSI (user-index): partition=userId, sort=sk — for querying by user
#   - TTL on "ttl" attribute — auto-expire old audit records (90 days default)
#   - PAY_PER_REQUEST billing — no capacity planning needed for POC
#
# Requirements: 14.18

resource "aws_dynamodb_table" "audit" {
  name         = "odot-dashboard-audit-${var.stage}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  # Partition key: app#stage (groups audit entries by application and stage)
  attribute {
    name = "pk"
    type = "S"
  }

  # Sort key: ISO 8601 timestamp (enables time-range queries within a partition)
  attribute {
    name = "sk"
    type = "S"
  }

  # GSI attribute: userId (enables querying all actions by a specific user)
  attribute {
    name = "userId"
    type = "S"
  }

  # Global Secondary Index for user-based queries
  # "Show me all actions performed by user X across all apps"
  global_secondary_index {
    name            = "user-index"
    hash_key        = "userId"
    range_key       = "sk"
    projection_type = "ALL"
  }

  # TTL: automatically expire audit records after the configured retention period.
  # The dashboard backend sets the ttl attribute to current_time + 90 days.
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery for audit data protection
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.merged_tags, {
    Name = "odot-dashboard-audit-${var.stage}"
  })
}
