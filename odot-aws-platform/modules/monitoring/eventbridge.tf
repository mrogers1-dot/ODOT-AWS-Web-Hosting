# modules/monitoring/eventbridge.tf
#
# EventBridge rule that captures Security Hub findings with Critical or High
# severity and routes them to the SNS alerts topic for notification via
# Slack (Chatbot) and email (ServiceNow/FortiSIEM).
#
# The design specifies notification within 5 minutes of a Critical/High
# Security Hub finding. EventBridge delivers events within seconds; SNS to
# Chatbot typically adds 10–30 seconds — well within the 5-minute SLA.
#
# Requirements: 9.9

# ── EventBridge Rule: Security Hub Critical/High Findings ─────────────────────
#
# Matches events from the aws.securityhub source where at least one finding
# has a severity label of CRITICAL or HIGH. This covers findings from
# GuardDuty, Inspector, Config, and Macie that are aggregated into Security Hub.
resource "aws_cloudwatch_event_rule" "securityhub_critical_high" {
  name        = "odot-securityhub-critical-high-${var.account_type}-${var.stage}"
  description = "Captures Security Hub findings with CRITICAL or HIGH severity for immediate notification"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL", "HIGH"]
        }
      }
    }
  })

  tags = local.merged_tags
}

# ── EventBridge Target: Route to SNS Topic ────────────────────────────────────
#
# Sends matched Security Hub findings to the SNS alerts topic. From there,
# notifications fan out to both the Slack channel (via Chatbot) and the
# email endpoint (for ServiceNow/FortiSIEM).
resource "aws_cloudwatch_event_target" "securityhub_to_sns" {
  rule      = aws_cloudwatch_event_rule.securityhub_critical_high.name
  target_id = "securityhub-sns-${var.account_type}-${var.stage}"
  arn       = aws_sns_topic.alerts.arn
}
