// Feature: odot-aws-web-hosting, Admin Dashboard application validation tests
//
// This file validates the admin-dashboard application structure:
//   - Required files exist (Dockerfile, package.json, server/, src/, README.md)
//   - Dockerfile runs as non-root user on port 3000
//   - CI/CD workflow exists with OIDC auth
//   - Backend has required route files
//   - Backend has auth and audit middleware
//
// Tests use file parsing — no AWS credentials required.
//
// Validates: Requirements 14.5, 14.6, 14.16, 14.18

package test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// dashboardAppPath returns the absolute path to the admin-dashboard directory.
func dashboardAppPath(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err)
	return filepath.Join(wd, "..", "..", "admin-dashboard")
}

// TestDashboardRequiredFilesExist asserts that all required application files
// are present in the admin-dashboard directory.
//
// Validates: Requirements 14.5
func TestDashboardRequiredFilesExist(t *testing.T) {
	t.Parallel()

	requiredFiles := []string{
		"package.json",
		"tsconfig.json",
		"Dockerfile",
		"README.md",
		"server/index.ts",
		"server/middleware/auth.ts",
		"server/middleware/auditLog.ts",
		"server/routes/apps.ts",
		"server/routes/actions.ts",
		"server/routes/logs.ts",
		"server/routes/audit.ts",
		"src/App.tsx",
		".github/workflows/ci-cd.yml",
	}

	for _, file := range requiredFiles {
		file := file
		t.Run(file, func(t *testing.T) {
			t.Parallel()
			fullPath := filepath.Join(dashboardAppPath(t), file)
			_, err := os.Stat(fullPath)
			assert.NoError(t, err, "required file %s must exist in admin-dashboard", file)
		})
	}
}

// TestDashboardDockerfileNonRoot asserts that the Dockerfile runs as non-root
// user on port 3000.
//
// Validates: Requirements 14.5
func TestDashboardDockerfileNonRoot(t *testing.T) {
	t.Parallel()

	dockerfilePath := filepath.Join(dashboardAppPath(t), "Dockerfile")
	content, err := os.ReadFile(dockerfilePath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: non-root user
	assert.Contains(t, contentStr, "USER 1000",
		"Dockerfile must run as non-root user (USER 1000)")

	// Assert: exposes port 3000
	assert.Contains(t, contentStr, "EXPOSE 3000",
		"Dockerfile must expose port 3000")

	// Assert: multi-stage build
	assert.True(t, strings.Count(contentStr, "FROM ") >= 2,
		"Dockerfile must use multi-stage build")

	// Assert: health check
	assert.Contains(t, contentStr, "HEALTHCHECK",
		"Dockerfile must include HEALTHCHECK instruction")
}

// TestDashboardCICDUsesOIDC asserts that the dashboard CI/CD workflow uses
// OIDC authentication.
//
// Validates: Requirements 14.6
func TestDashboardCICDUsesOIDC(t *testing.T) {
	t.Parallel()

	cicdPath := filepath.Join(dashboardAppPath(t), ".github/workflows/ci-cd.yml")
	content, err := os.ReadFile(cicdPath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: uses OIDC
	assert.Contains(t, contentStr, "role-to-assume",
		"dashboard CI/CD must use OIDC (role-to-assume)")

	// Assert: has scan job
	assert.Contains(t, contentStr, "scan",
		"dashboard CI/CD must have a security scan job")

	// Assert: has unit-test job
	assert.Contains(t, contentStr, "unit-test",
		"dashboard CI/CD must have a unit-test job")
}

// TestDashboardBackendHasRBAC asserts that the backend implements role-based
// access control via the auth middleware.
//
// Validates: Requirements 14.2, 14.3
func TestDashboardBackendHasRBAC(t *testing.T) {
	t.Parallel()

	authPath := filepath.Join(dashboardAppPath(t), "server/middleware/auth.ts")
	content, err := os.ReadFile(authPath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: role extraction from custom:role claim
	assert.Contains(t, contentStr, "custom:role",
		"auth middleware must extract role from custom:role claim")

	// Assert: Admin and Developer roles
	assert.Contains(t, contentStr, "Admin",
		"auth middleware must handle Admin role")
	assert.Contains(t, contentStr, "Developer",
		"auth middleware must handle Developer role")

	// Assert: stage-based access control
	assert.Contains(t, contentStr, "prod",
		"auth middleware must enforce prod-stage restrictions")
}

// TestDashboardBackendHasAuditLogging asserts that the backend logs all
// mutating operations to DynamoDB.
//
// Validates: Requirements 14.18
func TestDashboardBackendHasAuditLogging(t *testing.T) {
	t.Parallel()

	auditPath := filepath.Join(dashboardAppPath(t), "server/middleware/auditLog.ts")
	content, err := os.ReadFile(auditPath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: writes to DynamoDB
	assert.Contains(t, contentStr, "DynamoDB",
		"audit middleware must write to DynamoDB")

	// Assert: publishes to SNS
	assert.Contains(t, contentStr, "SNS",
		"audit middleware must publish to SNS")

	// Assert: captures mutating methods
	assert.Contains(t, contentStr, "POST",
		"audit middleware must capture POST requests")
}

// TestDashboardActionsRouteHasRollback asserts that the actions route
// includes rollback functionality requiring Admin role.
//
// Validates: Requirements 14.22
func TestDashboardActionsRouteHasRollback(t *testing.T) {
	t.Parallel()

	actionsPath := filepath.Join(dashboardAppPath(t), "server/routes/actions.ts")
	content, err := os.ReadFile(actionsPath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: rollback endpoint exists
	assert.Contains(t, contentStr, "rollback",
		"actions route must include rollback endpoint")

	// Assert: requires Admin role
	assert.Contains(t, contentStr, "requireRole('Admin')",
		"rollback must require Admin role")

	// Assert: WAF block/unblock endpoints exist
	assert.Contains(t, contentStr, "block-ip",
		"actions route must include block-ip endpoint")
	assert.Contains(t, contentStr, "unblock-ip",
		"actions route must include unblock-ip endpoint")
}
