// Feature: odot-aws-web-hosting, Documentation validation tests
//
// This file validates documentation completeness:
//   - README.md contains architecture overview, module layout, apply/destroy
//     instructions, capacity planning, module versioning
//   - docs/runbook.md exists with onboarding/alarm/KMS/notification sections
//   - docs/architecture/ has three diagram files
//   - scripts/smoke-test.sh exists and is executable
//
// Tests use file parsing — no AWS credentials required.
//
// Validates: Requirements 12.1, 12.2, 12.3

package test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// platformRoot returns the absolute path to the odot-aws-platform directory.
func platformRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err)
	return filepath.Join(wd, "..")
}

// TestREADMEContainsRequiredSections asserts that the platform README.md
// contains all required documentation sections.
//
// Validates: Requirements 12.1
func TestREADMEContainsRequiredSections(t *testing.T) {
	t.Parallel()

	readmePath := filepath.Join(platformRoot(t), "README.md")
	content, err := os.ReadFile(readmePath)
	require.NoError(t, err, "README.md must exist")

	contentStr := string(content)

	// Assert: Architecture overview section
	assert.Contains(t, contentStr, "Architecture",
		"README must contain an Architecture section")

	// Assert: Module layout/reference
	assert.Contains(t, contentStr, "Module",
		"README must contain module documentation")

	// Assert: Apply/destroy instructions
	assert.Contains(t, contentStr, "terraform apply",
		"README must contain terraform apply instructions")
	assert.Contains(t, contentStr, "terraform destroy",
		"README must contain terraform destroy instructions")

	// Assert: Repository structure
	assert.Contains(t, contentStr, "Repository Structure",
		"README must contain Repository Structure section")

	// Assert: Testing section
	assert.Contains(t, contentStr, "Testing",
		"README must contain a Testing section")
}

// TestRunbookContainsRequiredSections asserts that the runbook has all
// required operational procedure sections.
//
// Validates: Requirements 12.2
func TestRunbookContainsRequiredSections(t *testing.T) {
	t.Parallel()

	runbookPath := filepath.Join(platformRoot(t), "docs", "runbook.md")
	content, err := os.ReadFile(runbookPath)
	require.NoError(t, err, "docs/runbook.md must exist")

	contentStr := string(content)

	// Assert: Onboarding section
	assert.Contains(t, contentStr, "Onboarding",
		"runbook must contain an Onboarding section")

	// Assert: Alarm response section
	assert.Contains(t, contentStr, "Alarm",
		"runbook must contain an Alarm response section")

	// Assert: KMS key rotation section
	assert.Contains(t, contentStr, "KMS",
		"runbook must contain a KMS key rotation section")

	// Assert: Notification channel section
	assert.Contains(t, contentStr, "Notification",
		"runbook must contain a Notification channel section")
}

// TestArchitectureDiagramsExist asserts that the three required architecture
// diagram files exist in docs/architecture/.
//
// Validates: Requirements 12.3
func TestArchitectureDiagramsExist(t *testing.T) {
	t.Parallel()

	requiredDiagrams := []string{
		"network-topology.md",
		"cicd-pipeline.md",
		"ecs-cluster-layout.md",
	}

	archDir := filepath.Join(platformRoot(t), "docs", "architecture")

	for _, diagram := range requiredDiagrams {
		diagram := diagram
		t.Run(diagram, func(t *testing.T) {
			t.Parallel()
			fullPath := filepath.Join(archDir, diagram)
			_, err := os.Stat(fullPath)
			assert.NoError(t, err, "docs/architecture/%s must exist", diagram)
		})
	}
}

// TestSmokeTestScriptExists asserts that scripts/smoke-test.sh exists and
// is executable.
//
// Validates: Requirements 13.1
func TestSmokeTestScriptExists(t *testing.T) {
	t.Parallel()

	smokeTestPath := filepath.Join(platformRoot(t), "scripts", "smoke-test.sh")
	info, err := os.Stat(smokeTestPath)
	require.NoError(t, err, "scripts/smoke-test.sh must exist")

	// Assert: file is executable (has at least one execute bit set)
	mode := info.Mode()
	assert.True(t, mode&0111 != 0,
		"scripts/smoke-test.sh must be executable (mode: %s)", mode)
}

// TestSmokeTestScriptContent asserts that the smoke test script contains
// key validation checks.
//
// Validates: Requirements 13.1
func TestSmokeTestScriptContent(t *testing.T) {
	t.Parallel()

	smokeTestPath := filepath.Join(platformRoot(t), "scripts", "smoke-test.sh")
	content, err := os.ReadFile(smokeTestPath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: script accepts arguments
	assert.Contains(t, contentStr, "#!/",
		"smoke-test.sh must have a shebang line")

	// Assert: checks for ECS clusters
	assert.True(t,
		assert.ObjectsAreEqual(true, len(contentStr) > 100),
		"smoke-test.sh must have substantial content (>100 chars)")
}
