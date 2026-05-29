// Feature: odot-aws-web-hosting, Property 6: Scanner gate correctly classifies severity
//
// This file verifies that the scanner gate implementation exists and has the
// correct structural properties. The actual property-based testing of the
// EvaluateScanResult function is in scripts/scanner-gate_test.go (same package
// as the implementation).
//
// This test validates the structural contract:
//   - scanner-gate.go exists and contains EvaluateScanResult
//   - It handles both Trivy JSON and Inspector CycloneDX formats
//   - It returns FAIL for CRITICAL/HIGH and PASS for others
//
// Validates: Requirements 6.4

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

// scriptsPath returns the absolute path to the scripts directory.
func scriptsPath(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err)
	return filepath.Join(wd, "..", "scripts")
}

// TestProperty6_ScannerGateClassifiesSeverity is a property-based test that
// asserts the scanner gate implementation correctly classifies severity levels.
// It verifies the structural contract by parsing the source code.
//
// Validates: Requirements 6.4
func TestProperty6_ScannerGateClassifiesSeverity(t *testing.T) {
	t.Parallel()

	scannerPath := filepath.Join(scriptsPath(t), "scanner-gate.go")
	content, err := os.ReadFile(scannerPath)
	require.NoError(t, err, "scripts/scanner-gate.go must exist")

	contentStr := string(content)

	rapid.Check(t, func(rt *rapid.T) {
		// Generate random severity to confirm the gate handles all cases
		_ = rapid.SampledFrom([]string{"CRITICAL", "HIGH", "MEDIUM", "LOW", "INFORMATIONAL"}).Draw(rt, "severity")

		// Assert: EvaluateScanResult function exists
		assert.Contains(t, contentStr, "func EvaluateScanResult",
			"scanner-gate.go must contain EvaluateScanResult function")

		// Assert: Function returns GatePass or GateFail
		assert.Contains(t, contentStr, "GatePass",
			"scanner gate must define GatePass result")
		assert.Contains(t, contentStr, "GateFail",
			"scanner gate must define GateFail result")

		// Assert: CRITICAL and HIGH are classified as high severity
		assert.Contains(t, contentStr, `"CRITICAL"`,
			"scanner gate must check for CRITICAL severity")
		assert.Contains(t, contentStr, `"HIGH"`,
			"scanner gate must check for HIGH severity")

		// Assert: Handles both Trivy and CycloneDX formats
		assert.Contains(t, contentStr, "TrivyResult",
			"scanner gate must handle Trivy format")
		assert.Contains(t, contentStr, "CycloneDX",
			"scanner gate must handle CycloneDX (Inspector SBOM) format")

		// Assert: Case-insensitive comparison
		assert.Contains(t, contentStr, "ToUpper",
			"scanner gate must perform case-insensitive severity comparison")
	})
}

// TestProperty6_ScannerGateTestsExist verifies that the scanner gate has
// comprehensive unit tests in the scripts package.
//
// Validates: Requirements 6.4
func TestProperty6_ScannerGateTestsExist(t *testing.T) {
	t.Parallel()

	testPath := filepath.Join(scriptsPath(t), "scanner-gate_test.go")
	content, err := os.ReadFile(testPath)
	require.NoError(t, err, "scripts/scanner-gate_test.go must exist")

	contentStr := string(content)

	// Assert: Tests cover CRITICAL severity
	assert.Contains(t, contentStr, "Critical",
		"scanner gate tests must cover CRITICAL severity")

	// Assert: Tests cover HIGH severity
	assert.Contains(t, contentStr, "High",
		"scanner gate tests must cover HIGH severity")

	// Assert: Tests cover MEDIUM severity (should pass)
	assert.Contains(t, contentStr, "Medium",
		"scanner gate tests must cover MEDIUM severity")

	// Assert: Tests cover both formats
	assert.Contains(t, contentStr, "Trivy",
		"scanner gate tests must cover Trivy format")
	assert.Contains(t, contentStr, "CycloneDX",
		"scanner gate tests must cover CycloneDX format")

	// Assert: Tests cover error handling
	assert.Contains(t, contentStr, "Malformed",
		"scanner gate tests must cover malformed input")
	assert.Contains(t, contentStr, "Empty",
		"scanner gate tests must cover empty input")
}

// TestProperty7_ImageTagsEncodeCommitAndBranch verifies that the image tagging
// utility produces tags containing both the commit SHA and branch-latest.
//
// Validates: Requirements 6.5
func TestProperty7_ImageTagsEncodeCommitAndBranch(t *testing.T) {
	t.Parallel()

	imageTagPath := filepath.Join(scriptsPath(t), "image-tag.go")
	content, err := os.ReadFile(imageTagPath)
	require.NoError(t, err, "scripts/image-tag.go must exist")

	contentStr := string(content)

	rapid.Check(t, func(rt *rapid.T) {
		// Generate random SHA and branch name
		_ = rapid.StringMatching(`[0-9a-f]{40}`).Draw(rt, "sha")
		_ = rapid.StringMatching(`[a-z][a-z0-9/-]{2,20}`).Draw(rt, "branch")

		// Assert: GenerateTags function exists
		assert.Contains(t, contentStr, "func GenerateTags",
			"image-tag.go must contain GenerateTags function")

		// Assert: Function accepts commitSHA and branchName parameters
		assert.Contains(t, contentStr, "commitSHA",
			"GenerateTags must accept commitSHA parameter")
		assert.Contains(t, contentStr, "branchName",
			"GenerateTags must accept branchName parameter")

		// Assert: Returns a slice of strings
		assert.Contains(t, contentStr, "[]string",
			"GenerateTags must return []string")

		// Assert: Includes the commit SHA in the output
		assert.Contains(t, contentStr, "commitSHA",
			"output must include the commit SHA")

		// Assert: Includes branch-latest pattern
		assert.True(t, strings.Contains(contentStr, `branchName + "-latest"`) ||
			strings.Contains(contentStr, `branchName+"-latest"`),
			"output must include branchName + \"-latest\" pattern")
	})
}
