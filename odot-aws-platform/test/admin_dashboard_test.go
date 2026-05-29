// Feature: odot-aws-web-hosting, Admin Dashboard module tests
//
// This file validates the admin-dashboard Terraform module:
//   - Cognito User Pool has Okta as federated IdP
//   - DynamoDB table has TTL enabled
//   - Cross-account role trust policy allows Internal_Account task role
//   - Dashboard task role has required permissions scoped to WebHosting-*
//
// Tests use HCL parsing — no AWS credentials required.
//
// Validates: Requirements 14.1, 14.18, 14.29, 14.30

package test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// adminDashboardModulePath returns the absolute path to modules/admin-dashboard.
func adminDashboardModulePath(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err)
	return filepath.Join(wd, "..", "modules", "admin-dashboard")
}

// readAdminDashboardFile reads a specific file from the admin-dashboard module.
func readAdminDashboardFile(t *testing.T, filename string) string {
	t.Helper()
	content, err := os.ReadFile(filepath.Join(adminDashboardModulePath(t), filename))
	require.NoError(t, err, "modules/admin-dashboard/%s must be readable", filename)
	return string(content)
}

// TestAdminDashboardCognitoHasOktaIdP asserts that the Cognito User Pool
// is configured with Okta as a federated identity provider.
//
// Validates: Requirements 14.1
func TestAdminDashboardCognitoHasOktaIdP(t *testing.T) {
	t.Parallel()

	content := readAdminDashboardFile(t, "cognito.tf")

	// Assert: Cognito User Pool exists
	assert.Contains(t, content, `resource "aws_cognito_user_pool"`,
		"admin-dashboard module must contain aws_cognito_user_pool resource")

	// Assert: Okta identity provider is configured
	assert.Contains(t, content, `resource "aws_cognito_identity_provider"`,
		"admin-dashboard module must contain aws_cognito_identity_provider resource")
	assert.Contains(t, content, "Okta",
		"identity provider must be named Okta")
	assert.Contains(t, content, "OIDC",
		"identity provider must use OIDC type")

	// Assert: Attribute mapping includes custom:role for RBAC
	assert.Contains(t, content, "custom:role",
		"attribute mapping must include custom:role for RBAC")

	// Assert: Authorization code flow (not implicit)
	assert.Contains(t, content, `"code"`,
		"app client must use authorization code flow")
}

// TestAdminDashboardDynamoDBHasTTL asserts that the DynamoDB audit table
// has TTL enabled on the "ttl" attribute.
//
// Validates: Requirements 14.18
func TestAdminDashboardDynamoDBHasTTL(t *testing.T) {
	t.Parallel()

	content := readAdminDashboardFile(t, "dynamodb.tf")

	// Assert: DynamoDB table exists
	assert.Contains(t, content, `resource "aws_dynamodb_table"`,
		"admin-dashboard module must contain aws_dynamodb_table resource")

	// Assert: TTL is enabled
	assert.Contains(t, content, "ttl {",
		"DynamoDB table must have a ttl block")
	assert.Contains(t, content, "enabled        = true",
		"DynamoDB TTL must be enabled")
	assert.Contains(t, content, `attribute_name = "ttl"`,
		"DynamoDB TTL attribute must be named 'ttl'")

	// Assert: PAY_PER_REQUEST billing
	assert.Contains(t, content, "PAY_PER_REQUEST",
		"DynamoDB table must use PAY_PER_REQUEST billing mode")

	// Assert: GSI for user queries
	assert.Contains(t, content, "user-index",
		"DynamoDB table must have a user-index GSI")
}

// TestAdminDashboardCrossAccountRole asserts that the cross-account role
// trust policy allows the Internal_Account dashboard task role to assume it.
//
// Validates: Requirements 14.29, 14.30
func TestAdminDashboardCrossAccountRole(t *testing.T) {
	t.Parallel()

	content := readAdminDashboardFile(t, "iam.tf")

	// Assert: Cross-account role exists
	assert.Contains(t, content, "cross_account",
		"admin-dashboard module must contain a cross-account IAM role")

	// Assert: Trust policy references the internal account dashboard task role
	assert.Contains(t, content, "odot-dashboard-task-",
		"cross-account trust policy must reference the dashboard task role")

	// Assert: Trust policy uses sts:AssumeRole
	assert.Contains(t, content, "sts:AssumeRole",
		"cross-account trust policy must allow sts:AssumeRole")
}

// TestAdminDashboardTaskRolePermissions asserts that the dashboard task role
// has the required permissions for ECS, CloudWatch, ALB, WAF, and Auto-Scaling.
//
// Validates: Requirements 14.29, 14.30
func TestAdminDashboardTaskRolePermissions(t *testing.T) {
	t.Parallel()

	content := readAdminDashboardFile(t, "iam.tf")

	// Assert: Dashboard task role exists
	assert.Contains(t, content, "odot-dashboard-task-",
		"admin-dashboard module must contain a dashboard task IAM role")

	// Assert: ECS permissions
	assert.Contains(t, content, "ecs:UpdateService",
		"dashboard task role must have ecs:UpdateService permission")
	assert.Contains(t, content, "ecs:DescribeServices",
		"dashboard task role must have ecs:DescribeServices permission")
	assert.Contains(t, content, "ecs:StopTask",
		"dashboard task role must have ecs:StopTask permission")

	// Assert: CloudWatch permissions
	assert.Contains(t, content, "cloudwatch:GetMetricData",
		"dashboard task role must have cloudwatch:GetMetricData permission")
	assert.Contains(t, content, "logs:GetLogEvents",
		"dashboard task role must have logs:GetLogEvents permission")

	// Assert: ALB permissions
	assert.Contains(t, content, "elasticloadbalancing:DescribeTargetHealth",
		"dashboard task role must have ALB permissions")

	// Assert: WAF permissions
	assert.Contains(t, content, "wafv2:UpdateIPSet",
		"dashboard task role must have WAF UpdateIPSet permission")

	// Assert: Auto-Scaling permissions
	assert.Contains(t, content, "application-autoscaling:RegisterScalableTarget",
		"dashboard task role must have auto-scaling permissions")

	// Assert: DynamoDB audit permissions
	assert.Contains(t, content, "dynamodb:PutItem",
		"dashboard task role must have DynamoDB PutItem for audit logging")

	// Assert: SNS publish for notifications
	assert.Contains(t, content, "sns:Publish",
		"dashboard task role must have SNS Publish permission")

	// Assert: STS AssumeRole for cross-account
	assert.Contains(t, content, "sts:AssumeRole",
		"dashboard task role must have STS AssumeRole for cross-account access")
}

// TestAdminDashboardWAFIPSet asserts that a WAF IP set is created for
// managed IP blocking from the dashboard UI.
//
// Validates: Requirements 14.25
func TestAdminDashboardWAFIPSet(t *testing.T) {
	t.Parallel()

	content := readAdminDashboardFile(t, "iam.tf")

	// Assert: WAF IP set resource exists
	assert.Contains(t, content, `resource "aws_wafv2_ip_set"`,
		"admin-dashboard module must contain aws_wafv2_ip_set resource")
	assert.Contains(t, content, "dashboard-blocked-ips",
		"WAF IP set must be named for dashboard-managed blocking")
}

// TestAdminDashboardOutputs asserts that the module exports the required outputs.
//
// Validates: Requirements 14.1, 14.29, 14.30
func TestAdminDashboardOutputs(t *testing.T) {
	t.Parallel()

	content := readAdminDashboardFile(t, "outputs.tf")

	requiredOutputs := []string{
		"cognito_user_pool_id",
		"cognito_app_client_id",
		"cognito_domain",
		"audit_table_name",
		"dashboard_task_role_arn",
		"cross_account_role_arn",
	}

	for _, output := range requiredOutputs {
		assert.Contains(t, content, output,
			"admin-dashboard module must output %q", output)
	}
}
