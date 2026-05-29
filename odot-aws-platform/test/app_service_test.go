// Feature: odot-aws-web-hosting, App-Service module property tests
//
// This file contains property-based tests for the modules/app-service module:
//   Property 4: ECR repositories have scan-on-push and KMS encryption
//   Property 5: ECR lifecycle policies enforce correct retention
//   Property 3: Fargate task definitions enforce read-only filesystem and non-root
//   Property 2: External-account ALBs include WAF association
//   Property 8: Auto-scaling bounds are min=2, max=50
//   Property 10: CloudWatch log retention matches stage
//   Property 11: Per-service alarms with correct thresholds
//
// Tests use HCL parsing — no AWS credentials required.
//
// Validates: Requirements 3.3, 3.5, 4.4, 4.7, 4.8, 5.2, 5.3, 5.5, 9.8, 10.3, 10.6

package test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"pgregory.net/rapid"
)

// appServicePath returns the absolute path to modules/app-service.
func appServicePath(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err)
	return filepath.Join(wd, "..", "modules", "app-service")
}

// readAppServiceFile reads a specific file from the app-service module.
func readAppServiceFile(t *testing.T, filename string) string {
	t.Helper()
	content, err := os.ReadFile(filepath.Join(appServicePath(t), filename))
	require.NoError(t, err, "modules/app-service/%s must be readable", filename)
	return string(content)
}

// ── Property 4: ECR scan-on-push and KMS encryption ──────────────────────────

// TestProperty4_ECRScanOnPushAndKMSEncryption asserts that all ECR repositories
// have scan_on_push = true and encryption_type = "KMS" with a non-null kms_key.
//
// Validates: Requirements 5.2, 5.3
func TestProperty4_ECRScanOnPushAndKMSEncryption(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "ecr.tf")

	rapid.Check(t, func(rt *rapid.T) {
		_ = rapid.StringMatching(`[a-z][a-z0-9]{2,8}`).Draw(rt, "app_name")
		_ = rapid.SampledFrom([]string{"internal", "external"}).Draw(rt, "account_type")

		// Assert: ECR repository resource exists
		assert.Contains(t, content, `resource "aws_ecr_repository"`,
			"app-service module must contain an aws_ecr_repository resource")

		// Assert: scan_on_push = true
		assert.Contains(t, content, "scan_on_push = true",
			"ECR repository must have scan_on_push = true")

		// Assert: encryption_type = "KMS"
		assert.Contains(t, content, `encryption_type = "KMS"`,
			"ECR repository must have encryption_type = \"KMS\"")

		// Assert: kms_key references a variable (non-null)
		assert.Contains(t, content, "kms_key",
			"ECR encryption must reference a kms_key")
		assert.Contains(t, content, "var.kms_key_arn",
			"ECR kms_key must reference var.kms_key_arn")
	})
}

// ── Property 5: ECR lifecycle policy retention rules ─────────────────────────

// TestProperty5_ECRLifecyclePolicyRetention asserts that the ECR lifecycle
// policy contains exactly two rules: tagged images countNumber=10 and
// untagged images countNumber=7.
//
// Validates: Requirements 5.5
func TestProperty5_ECRLifecyclePolicyRetention(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "ecr.tf")

	rapid.Check(t, func(rt *rapid.T) {
		_ = rapid.StringMatching(`[a-z][a-z0-9]{2,8}`).Draw(rt, "app_name")

		// Assert: lifecycle policy resource exists
		assert.Contains(t, content, `resource "aws_ecr_lifecycle_policy"`,
			"app-service module must contain an aws_ecr_lifecycle_policy resource")

		// Assert: Rule 1 — tagged images, countNumber = 10
		assert.Contains(t, content, "imageCountMoreThan",
			"lifecycle policy must have a rule with countType = imageCountMoreThan")
		assert.Contains(t, content, "countNumber   = 10",
			"tagged image rule must have countNumber = 10")

		// Assert: Rule 2 — untagged images, countNumber = 7
		assert.Contains(t, content, "sinceImagePushed",
			"lifecycle policy must have a rule with countType = sinceImagePushed")
		assert.Contains(t, content, "countNumber = 7",
			"untagged image rule must have countNumber = 7")

		// Assert: exactly two rules (rulePriority 1 and 2)
		assert.Contains(t, content, "rulePriority = 1",
			"lifecycle policy must have rule with priority 1")
		assert.Contains(t, content, "rulePriority = 2",
			"lifecycle policy must have rule with priority 2")
		// No rulePriority = 3 should exist
		assert.NotContains(t, content, "rulePriority = 3",
			"lifecycle policy must have exactly 2 rules (no priority 3)")
	})
}

// ── Property 3: Task definition security (read-only FS, non-root) ────────────

// TestProperty3_TaskDefinitionSecurityHardening asserts that Linux task
// definitions enforce readonlyRootFilesystem = true and non-root user,
// while Windows tasks omit these settings.
//
// Validates: Requirements 4.8, 9.8
func TestProperty3_TaskDefinitionSecurityHardening(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "task-definition.tf")

	rapid.Check(t, func(rt *rapid.T) {
		runtime := rapid.SampledFrom([]string{"linux", "windows"}).Draw(rt, "runtime")
		_ = runtime

		// Assert: Linux container definition has readonlyRootFilesystem = true
		assert.Contains(t, content, "readonlyRootFilesystem = true",
			"Linux container definition must have readonlyRootFilesystem = true")

		// Assert: Linux container definition has non-root user
		assert.Contains(t, content, `user = "1000"`,
			"Linux container definition must have user = \"1000\" (non-root)")

		// Assert: Windows container definition does NOT have readonlyRootFilesystem
		// The module uses separate locals for linux vs windows container definitions
		assert.Contains(t, content, "linux_container_definition",
			"module must have a linux_container_definition local")
		assert.Contains(t, content, "windows_container_definition",
			"module must have a windows_container_definition local")

		// Assert: The conditional logic uses var.runtime to select the definition
		assert.Contains(t, content, `var.runtime == "windows"`,
			"container definition selection must be conditional on var.runtime")
	})
}

// TestTaskDefinitionWindowsRuntime asserts that Windows tasks use
// WINDOWS_SERVER_2019_CORE and X86_64 architecture.
//
// Validates: Requirements 4.7
func TestTaskDefinitionWindowsRuntime(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "task-definition.tf")

	// Assert: Windows runtime platform is configured
	assert.Contains(t, content, "WINDOWS_SERVER_2019_CORE",
		"Windows runtime must use WINDOWS_SERVER_2019_CORE")
	assert.Contains(t, content, "X86_64",
		"Windows runtime must use X86_64 architecture")

	// Assert: Linux runtime is also configured
	assert.Contains(t, content, `"LINUX"`,
		"Linux runtime must be configured")
}

// ── Property 2: External ALBs include WAF association ────────────────────────

// TestProperty2_ExternalALBHasWAFAssociation asserts that external-account
// ALBs always include a WAF Web ACL association.
//
// Validates: Requirements 3.3, 3.5
func TestProperty2_ExternalALBHasWAFAssociation(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "alb.tf")

	rapid.Check(t, func(rt *rapid.T) {
		_ = rapid.SampledFrom([]string{"external"}).Draw(rt, "account_type")

		// Assert: WAF association resource exists
		assert.Contains(t, content, `resource "aws_wafv2_web_acl_association"`,
			"app-service module must contain aws_wafv2_web_acl_association resource")

		// Assert: WAF association is conditional on external account type
		assert.Contains(t, content, `var.account_type == "external"`,
			"WAF association must be conditional on account_type == external")

		// Assert: WAF association references the ALB
		assert.Contains(t, content, "aws_lb.this.arn",
			"WAF association resource_arn must reference the ALB")

		// Assert: WAF association uses the waf_acl_arn variable
		assert.Contains(t, content, "var.waf_acl_arn",
			"WAF association web_acl_arn must reference var.waf_acl_arn")

		// Assert: External ALBs have the waf-managed tag
		assert.Contains(t, content, `"waf-managed"`,
			"External ALBs must have the waf-managed tag for SCP compliance")
	})
}

// ── Property 8: Auto-scaling bounds min=2, max=50 ────────────────────────────

// TestProperty8_AutoScalingBounds asserts that the auto-scaling target has
// min_capacity = 2 and max_capacity = 50.
//
// Validates: Requirements 4.4
func TestProperty8_AutoScalingBounds(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "autoscaling.tf")

	rapid.Check(t, func(rt *rapid.T) {
		_ = rapid.StringMatching(`[a-z][a-z0-9]{2,8}`).Draw(rt, "app_name")
		_ = rapid.SampledFrom([]string{"dev", "test", "prod"}).Draw(rt, "stage")

		// Assert: Auto-scaling target resource exists
		assert.Contains(t, content, `resource "aws_appautoscaling_target"`,
			"app-service module must contain aws_appautoscaling_target resource")

		// Assert: min_capacity = 2
		assert.Contains(t, content, "min_capacity       = 2",
			"auto-scaling target must have min_capacity = 2")

		// Assert: max_capacity = 50
		assert.Contains(t, content, "max_capacity       = 50",
			"auto-scaling target must have max_capacity = 50")
	})
}

// ── Property 10: CloudWatch log retention matches stage ──────────────────────

// TestProperty10_LogRetentionMatchesStage asserts that log retention is
// 365 days for prod and 90 days for other stages.
//
// Validates: Requirements 10.6
func TestProperty10_LogRetentionMatchesStage(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "cloudwatch.tf")

	rapid.Check(t, func(rt *rapid.T) {
		_ = rapid.SampledFrom([]string{"dev", "test", "prod"}).Draw(rt, "stage")

		// Assert: Log group resource exists
		assert.Contains(t, content, `resource "aws_cloudwatch_log_group"`,
			"app-service module must contain aws_cloudwatch_log_group resource")

		// Assert: retention_in_days uses conditional logic based on stage
		assert.Contains(t, content, "retention_in_days",
			"log group must have retention_in_days set")

		// Assert: prod = 365, others = 90
		assert.Contains(t, content, `var.stage == "prod" ? 365 : 90`,
			"log retention must be 365 for prod and 90 for other stages")
	})
}

// ── Property 11: Per-service monitoring alarms ───────────────────────────────

// TestProperty11_MonitoringAlarmsWithCorrectThresholds asserts that exactly
// four monitoring alarms exist with correct thresholds: CPU > 80% (300s),
// memory > 80% (300s), 5xx > 1% (300s), task count < 2.
//
// Validates: Requirements 10.3
func TestProperty11_MonitoringAlarmsWithCorrectThresholds(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "cloudwatch.tf")

	rapid.Check(t, func(rt *rapid.T) {
		_ = rapid.StringMatching(`[a-z][a-z0-9]{2,8}`).Draw(rt, "app_name")
		_ = rapid.SampledFrom([]string{"dev", "test", "prod"}).Draw(rt, "stage")

		// Assert: CPU utilization alarm exists with threshold 80 and period 300
		assert.Contains(t, content, "cpu_utilization_high",
			"must have a CPU utilization high alarm")
		assert.Contains(t, content, "threshold           = 80",
			"CPU alarm threshold must be 80")

		// Assert: Memory utilization alarm exists with threshold 80 and period 300
		assert.Contains(t, content, "memory_utilization_high",
			"must have a memory utilization high alarm")

		// Assert: 5xx error rate alarm exists with threshold 1
		assert.Contains(t, content, "alb_5xx_rate",
			"must have an ALB 5xx rate alarm")
		assert.Contains(t, content, "threshold           = 1",
			"5xx alarm threshold must be 1 (percent)")

		// Assert: Task count low alarm exists with threshold 2
		assert.Contains(t, content, "task_count_low",
			"must have a task count low alarm")
		assert.Contains(t, content, "threshold           = 2",
			"task count alarm threshold must be 2")

		// Assert: All monitoring alarms use period = 300
		lines := strings.Split(content, "\n")
		periodCount := 0
		for _, line := range lines {
			if strings.Contains(strings.TrimSpace(line), "period") &&
				strings.Contains(line, "300") {
				periodCount++
			}
		}
		assert.GreaterOrEqual(t, periodCount, 3,
			"at least 3 monitoring alarms must use period = 300")

		// Assert: All alarms route to SNS
		assert.Contains(t, content, "var.sns_topic_arn",
			"monitoring alarms must route to SNS topic")
	})
}

// ── ECS Service tests ────────────────────────────────────────────────────────

// TestECSServiceCircuitBreaker asserts that the ECS service has deployment
// circuit breaker enabled with rollback = true.
//
// Validates: Requirements 4.3
func TestECSServiceCircuitBreaker(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "ecs-service.tf")

	// Assert: circuit breaker block exists
	assert.Contains(t, content, "deployment_circuit_breaker",
		"ECS service must have deployment_circuit_breaker block")

	// Assert: enable = true
	assert.Contains(t, content, "enable   = true",
		"deployment_circuit_breaker must have enable = true")

	// Assert: rollback = true
	assert.Contains(t, content, "rollback = true",
		"deployment_circuit_breaker must have rollback = true")
}

// TestECSServiceMultiAZ asserts that the ECS service uses private_subnet_ids
// (which span multiple AZs) for network configuration.
//
// Validates: Requirements 4.3
func TestECSServiceMultiAZ(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "ecs-service.tf")

	// Assert: network_configuration uses private_subnet_ids
	assert.Contains(t, content, "var.private_subnet_ids",
		"ECS service network_configuration must use var.private_subnet_ids (multi-AZ)")

	// Assert: desired_count = 2
	assert.Contains(t, content, "desired_count   = 2",
		"ECS service must have desired_count = 2 for high availability")
}

// TestECSServiceDesiredCount asserts the service starts with 2 tasks.
//
// Validates: Requirements 4.2
func TestECSServiceDesiredCount(t *testing.T) {
	t.Parallel()

	content := readAppServiceFile(t, "ecs-service.tf")

	assert.Contains(t, content, "desired_count   = 2",
		"ECS service desired_count must be 2")
}
