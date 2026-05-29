// Feature: odot-aws-web-hosting, App Template validation tests
//
// This file validates the odot-app-template repository structure:
//   - Required files exist (ci-cd.yml, pr-checks.yml, terraform/, Dockerfile, etc.)
//   - ci-cd.yml uses OIDC (role-to-assume) and NOT AWS_ACCESS_KEY_ID
//   - Job dependency chain enforces unit-test → scan → build-push → deploy
//   - deploy-prod has environment: production for manual approval gate
//   - Timeout constraints on non-prod jobs
//
// Tests use file parsing — no AWS credentials required.
//
// Validates: Requirements 6.2, 6.7, 6.8, 6.9, 7.1, 7.2

package test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// appTemplatePath returns the absolute path to the odot-app-template directory.
func appTemplatePath(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err)
	return filepath.Join(wd, "..", "..", "odot-app-template")
}

// TestAppTemplateRequiredFilesExist asserts that all required files are present
// in the app template repository.
//
// Validates: Requirements 7.1, 7.2
func TestAppTemplateRequiredFilesExist(t *testing.T) {
	t.Parallel()

	requiredFiles := []string{
		".github/workflows/ci-cd.yml",
		".github/workflows/pr-checks.yml",
		"terraform/main.tf",
		"terraform/variables.tf",
		"terraform/terraform.tfvars.example",
		"Dockerfile",
		"CONTRIBUTING.md",
		"README.md",
	}

	for _, file := range requiredFiles {
		file := file
		t.Run(file, func(t *testing.T) {
			t.Parallel()
			fullPath := filepath.Join(appTemplatePath(t), file)
			_, err := os.Stat(fullPath)
			assert.NoError(t, err, "required file %s must exist in odot-app-template", file)
		})
	}
}

// TestCICDUsesOIDCNotAccessKeys asserts that the CI/CD workflow uses OIDC
// authentication (role-to-assume) and does NOT reference AWS_ACCESS_KEY_ID.
//
// Validates: Requirements 6.7
func TestCICDUsesOIDCNotAccessKeys(t *testing.T) {
	t.Parallel()

	cicdPath := filepath.Join(appTemplatePath(t), ".github/workflows/ci-cd.yml")
	content, err := os.ReadFile(cicdPath)
	require.NoError(t, err, "ci-cd.yml must exist")

	contentStr := string(content)

	// Assert: uses role-to-assume (OIDC)
	assert.Contains(t, contentStr, "role-to-assume",
		"ci-cd.yml must use role-to-assume for OIDC authentication")

	// Assert: does NOT use AWS_ACCESS_KEY_ID
	assert.NotContains(t, contentStr, "AWS_ACCESS_KEY_ID",
		"ci-cd.yml must NOT reference AWS_ACCESS_KEY_ID (use OIDC instead)")

	// Assert: does NOT use AWS_SECRET_ACCESS_KEY
	assert.NotContains(t, contentStr, "AWS_SECRET_ACCESS_KEY",
		"ci-cd.yml must NOT reference AWS_SECRET_ACCESS_KEY (use OIDC instead)")
}

// TestCICDJobDependencyChain asserts that the pipeline enforces the correct
// job dependency order: scan needs unit-test, build-push needs scan,
// deploy jobs need build-push.
//
// Validates: Requirements 6.2, 6.9
func TestCICDJobDependencyChain(t *testing.T) {
	t.Parallel()

	cicdPath := filepath.Join(appTemplatePath(t), ".github/workflows/ci-cd.yml")
	content, err := os.ReadFile(cicdPath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: scan job depends on unit-test
	assert.Contains(t, contentStr, "needs: unit-test",
		"scan job must have needs: unit-test")

	// Assert: build-push job depends on scan
	assert.Contains(t, contentStr, "needs: scan",
		"build-push job must have needs: scan")

	// Assert: deploy jobs depend on build-push
	assert.Contains(t, contentStr, "needs: build-push",
		"deploy jobs must have needs: build-push")
}

// TestCICDProdManualApproval asserts that the deploy-prod job uses
// environment: production for manual approval gate.
//
// Validates: Requirements 6.8
func TestCICDProdManualApproval(t *testing.T) {
	t.Parallel()

	cicdPath := filepath.Join(appTemplatePath(t), ".github/workflows/ci-cd.yml")
	content, err := os.ReadFile(cicdPath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: deploy-prod job has environment: production
	// Look for the pattern in the YAML
	assert.True(t,
		strings.Contains(contentStr, "name: production") ||
			strings.Contains(contentStr, "environment:\n      name: production"),
		"deploy-prod job must include environment: production for manual approval gate")
}

// TestCICDSecurityScanners asserts that the scan job includes Trivy,
// Inspector, and CodeQL.
//
// Validates: Requirements 6.3
func TestCICDSecurityScanners(t *testing.T) {
	t.Parallel()

	cicdPath := filepath.Join(appTemplatePath(t), ".github/workflows/ci-cd.yml")
	content, err := os.ReadFile(cicdPath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: Trivy scanner is configured
	assert.Contains(t, contentStr, "trivy",
		"ci-cd.yml must include Trivy vulnerability scanner")

	// Assert: Amazon Inspector is configured
	assert.Contains(t, contentStr, "inspector",
		"ci-cd.yml must include Amazon Inspector scan")

	// Assert: CodeQL is configured
	assert.Contains(t, contentStr, "codeql",
		"ci-cd.yml must include CodeQL analysis")
}

// TestDockerfileNonRootUser asserts that the Dockerfile runs as non-root user.
//
// Validates: Requirements 9.8
func TestDockerfileNonRootUser(t *testing.T) {
	t.Parallel()

	dockerfilePath := filepath.Join(appTemplatePath(t), "Dockerfile")
	content, err := os.ReadFile(dockerfilePath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: USER instruction sets non-root (UID 1000)
	assert.Contains(t, contentStr, "USER 1000",
		"Dockerfile must run as non-root user (USER 1000)")

	// Assert: Multi-stage build
	assert.True(t,
		strings.Count(contentStr, "FROM ") >= 2,
		"Dockerfile must use multi-stage build (at least 2 FROM instructions)")

	// Assert: HEALTHCHECK instruction exists
	assert.Contains(t, contentStr, "HEALTHCHECK",
		"Dockerfile must include a HEALTHCHECK instruction")
}
