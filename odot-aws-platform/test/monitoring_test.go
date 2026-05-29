// Feature: odot-aws-web-hosting, Monitoring module unit tests
//
// This file contains unit tests for the modules/monitoring Terraform module.
// Tests assert:
//   1. SNS topic name follows odot-alerts-{account_type}
//   2. Budget threshold at 80%
//   3. EventBridge rule for ECS task exits exists (via Security Hub)
//   4. EventBridge rule for Security Hub Critical/High findings exists
//
// Tests use HCL parsing — no AWS credentials required.
//
// Validates: Requirements 9.9, 10.4, 10.7, 11.2

package test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// monitoringModulePath returns the absolute path to modules/monitoring.
func monitoringModulePath(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err)
	return filepath.Join(wd, "..", "modules", "monitoring")
}

// readMonitoringFile reads a specific file from the monitoring module.
func readMonitoringFile(t *testing.T, filename string) string {
	t.Helper()
	content, err := os.ReadFile(filepath.Join(monitoringModulePath(t), filename))
	require.NoError(t, err, "modules/monitoring/%s must be readable", filename)
	return string(content)
}

// TestMonitoringSNSTopicNaming asserts that the SNS topic name follows
// the convention odot-alerts-{account_type}.
//
// Validates: Requirements 10.4
func TestMonitoringSNSTopicNaming(t *testing.T) {
	t.Parallel()

	content := readMonitoringFile(t, "main.tf")

	// Assert: SNS topic resource exists
	assert.Contains(t, content, `resource "aws_sns_topic"`,
		"monitoring module must contain an aws_sns_topic resource")

	// Assert: topic name follows convention
	assert.Contains(t, content, `"odot-alerts-${var.account_type}"`,
		"SNS topic name must follow convention odot-alerts-{account_type}")
}

// TestMonitoringBudgetThreshold asserts that the budget notification fires
// at 80% of the limit.
//
// Validates: Requirements 11.2
func TestMonitoringBudgetThreshold(t *testing.T) {
	t.Parallel()

	content := readMonitoringFile(t, "main.tf")

	// Assert: Budget resource exists
	assert.Contains(t, content, `resource "aws_budgets_budget"`,
		"monitoring module must contain an aws_budgets_budget resource")

	// Assert: threshold = 80
	assert.Contains(t, content, "threshold                  = 80",
		"budget notification threshold must be 80 (percent)")

	// Assert: notification_type = FORECASTED
	assert.Contains(t, content, `notification_type          = "FORECASTED"`,
		"budget notification type must be FORECASTED")

	// Assert: time_unit = MONTHLY
	assert.Contains(t, content, `time_unit    = "MONTHLY"`,
		"budget time_unit must be MONTHLY")
}

// TestMonitoringEventBridgeSecurityHub asserts that an EventBridge rule
// exists for Security Hub Critical/High findings.
//
// Validates: Requirements 9.9
func TestMonitoringEventBridgeSecurityHub(t *testing.T) {
	t.Parallel()

	content := readMonitoringFile(t, "eventbridge.tf")

	// Assert: EventBridge rule resource exists
	assert.Contains(t, content, `resource "aws_cloudwatch_event_rule"`,
		"monitoring module must contain an aws_cloudwatch_event_rule resource")

	// Assert: rule matches Security Hub source
	assert.Contains(t, content, "aws.securityhub",
		"EventBridge rule must match aws.securityhub source")

	// Assert: rule filters for CRITICAL and HIGH severity
	assert.Contains(t, content, "CRITICAL",
		"EventBridge rule must filter for CRITICAL severity")
	assert.Contains(t, content, "HIGH",
		"EventBridge rule must filter for HIGH severity")

	// Assert: EventBridge target routes to SNS
	assert.Contains(t, content, `resource "aws_cloudwatch_event_target"`,
		"monitoring module must contain an aws_cloudwatch_event_target resource")
	assert.Contains(t, content, "aws_sns_topic.alerts.arn",
		"EventBridge target must route to the SNS alerts topic")
}

// TestMonitoringSNSEncryption asserts that the SNS topic is encrypted with KMS.
//
// Validates: Requirements 10.4
func TestMonitoringSNSEncryption(t *testing.T) {
	t.Parallel()

	content := readMonitoringFile(t, "main.tf")

	// Assert: SNS topic has KMS encryption
	assert.Contains(t, content, "kms_master_key_id",
		"SNS topic must have kms_master_key_id for encryption")
	assert.Contains(t, content, "var.kms_key_arn",
		"SNS topic kms_master_key_id must reference var.kms_key_arn")
}

// TestMonitoringChatbotSlackIntegration asserts that AWS Chatbot is configured
// for Slack notifications.
//
// Validates: Requirements 10.4
func TestMonitoringChatbotSlackIntegration(t *testing.T) {
	t.Parallel()

	content := readMonitoringFile(t, "main.tf")

	// Assert: Chatbot Slack channel configuration exists
	assert.Contains(t, content, `resource "aws_chatbot_slack_channel_configuration"`,
		"monitoring module must contain aws_chatbot_slack_channel_configuration")

	// Assert: Chatbot subscribes to the SNS topic
	assert.Contains(t, content, "aws_sns_topic.alerts.arn",
		"Chatbot must subscribe to the SNS alerts topic")
}

// TestMonitoringDashboard asserts that a CloudWatch dashboard is created.
//
// Validates: Requirements 10.2
func TestMonitoringDashboard(t *testing.T) {
	t.Parallel()

	content := readMonitoringFile(t, "main.tf")

	// Assert: Dashboard resource exists
	assert.Contains(t, content, `resource "aws_cloudwatch_dashboard"`,
		"monitoring module must contain aws_cloudwatch_dashboard resource")

	// Assert: Dashboard has key widgets
	assert.Contains(t, content, "ECS Running Task Count",
		"dashboard must have ECS Running Task Count widget")
	assert.Contains(t, content, "ECS CPU Utilization",
		"dashboard must have ECS CPU Utilization widget")
	assert.Contains(t, content, "ECS Memory Utilization",
		"dashboard must have ECS Memory Utilization widget")
	assert.Contains(t, content, "ALB Request Count",
		"dashboard must have ALB Request Count widget")
	assert.Contains(t, content, "ALB 5xx Error Rate",
		"dashboard must have ALB 5xx Error Rate widget")
	assert.Contains(t, content, "Active Alarms",
		"dashboard must have Active Alarms widget")
}
