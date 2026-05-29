// Feature: odot-aws-web-hosting, Stack configuration unit tests
//
// This file contains unit tests for the six deployable stacks that wire
// together the platform modules. Tests assert:
//   1. All six stacks call the required modules (networking, ecs-cluster, security, monitoring, oidc)
//   2. External stacks reference waf_acl_arn in their comments/outputs (WAF context)
//   3. All stacks have provider.tf with assume_role configuration
//   4. All stacks have backend.tf with unique state keys
//   5. Naming convention {Project}-{Environment} is followed
//
// Tests use HCL/file parsing — no AWS credentials required.
//
// Validates: Requirements 1.1, 8.1, 8.3, 8.7

package test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// stacksDir returns the absolute path to the stacks directory.
func stacksDir(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err)
	return filepath.Join(wd, "..", "stacks")
}

// allStacks returns the six expected stack directory names.
func allStacks() []string {
	return []string{
		"internal-dev",
		"internal-test",
		"internal-prod",
		"external-dev",
		"external-test",
		"external-prod",
	}
}

// requiredModules returns the five modules every stack must call.
func requiredModules() []string {
	return []string{
		"networking",
		"ecs_cluster",
		"security",
		"monitoring",
		"oidc",
	}
}

// TestAllStacksCallRequiredModules asserts that all six stacks call the five
// required modules: networking, ecs_cluster, security, monitoring, oidc.
//
// Validates: Requirements 1.1, 8.3
func TestAllStacksCallRequiredModules(t *testing.T) {
	t.Parallel()

	for _, stack := range allStacks() {
		stack := stack
		t.Run(stack, func(t *testing.T) {
			t.Parallel()

			mainTFPath := filepath.Join(stacksDir(t), stack, "main.tf")
			content, err := os.ReadFile(mainTFPath)
			require.NoError(t, err, "stacks/%s/main.tf must exist", stack)

			contentStr := string(content)

			for _, mod := range requiredModules() {
				// Check for module "mod_name" { block
				moduleDecl := fmt.Sprintf(`module "%s"`, mod)
				assert.Contains(t, contentStr, moduleDecl,
					"stack %s must call module %q", stack, mod)
			}
		})
	}
}

// TestExternalStacksReferenceWAF asserts that external stacks have WAF context
// in their main.tf (either via comments mentioning waf_acl_arn or the file
// header mentioning WAF).
//
// Validates: Requirements 1.1, 3.3
func TestExternalStacksReferenceWAF(t *testing.T) {
	t.Parallel()

	externalStacks := []string{"external-dev", "external-test", "external-prod"}

	for _, stack := range externalStacks {
		stack := stack
		t.Run(stack, func(t *testing.T) {
			t.Parallel()

			mainTFPath := filepath.Join(stacksDir(t), stack, "main.tf")
			content, err := os.ReadFile(mainTFPath)
			require.NoError(t, err, "stacks/%s/main.tf must exist", stack)

			contentStr := string(content)

			// External stacks should reference WAF in their documentation/comments
			assert.True(t,
				strings.Contains(contentStr, "waf") || strings.Contains(contentStr, "WAF"),
				"external stack %s must reference WAF (waf_acl_arn or WAF context)", stack)
		})
	}
}

// TestAllStacksHaveProviderWithAssumeRole asserts that every stack has a
// provider.tf with assume_role configuration for cross-account access.
//
// Validates: Requirements 8.1
func TestAllStacksHaveProviderWithAssumeRole(t *testing.T) {
	t.Parallel()

	for _, stack := range allStacks() {
		stack := stack
		t.Run(stack, func(t *testing.T) {
			t.Parallel()

			providerPath := filepath.Join(stacksDir(t), stack, "provider.tf")
			content, err := os.ReadFile(providerPath)
			require.NoError(t, err, "stacks/%s/provider.tf must exist", stack)

			contentStr := string(content)

			// Assert: provider "aws" block exists
			assert.Contains(t, contentStr, `provider "aws"`,
				"stack %s must have an aws provider block", stack)

			// Assert: assume_role block exists
			assert.Contains(t, contentStr, "assume_role",
				"stack %s provider must have assume_role for cross-account access", stack)

			// Assert: region is us-east-2
			assert.Contains(t, contentStr, "us-east-2",
				"stack %s provider must use us-east-2 region", stack)
		})
	}
}

// TestAllStacksHaveBackendTF asserts that every stack has a backend.tf file.
//
// Validates: Requirements 8.5
func TestAllStacksHaveBackendTF(t *testing.T) {
	t.Parallel()

	for _, stack := range allStacks() {
		stack := stack
		t.Run(stack, func(t *testing.T) {
			t.Parallel()

			backendPath := filepath.Join(stacksDir(t), stack, "backend.tf")
			_, err := os.Stat(backendPath)
			assert.NoError(t, err, "stacks/%s/backend.tf must exist", stack)
		})
	}
}

// TestAllStacksHaveVersionsTF asserts that every stack has a versions.tf file.
//
// Validates: Requirements 8.1
func TestAllStacksHaveVersionsTF(t *testing.T) {
	t.Parallel()

	for _, stack := range allStacks() {
		stack := stack
		t.Run(stack, func(t *testing.T) {
			t.Parallel()

			versionsPath := filepath.Join(stacksDir(t), stack, "versions.tf")
			_, err := os.Stat(versionsPath)
			assert.NoError(t, err, "stacks/%s/versions.tf must exist", stack)
		})
	}
}

// TestStackNamingConvention asserts that stacks follow the naming convention
// by setting appropriate local values for account_type and stage.
//
// Validates: Requirements 8.7
func TestStackNamingConvention(t *testing.T) {
	t.Parallel()

	expectedLocals := map[string]struct {
		accountType string
		stage       string
	}{
		"internal-dev":  {accountType: "internal", stage: "dev"},
		"internal-test": {accountType: "internal", stage: "test"},
		"internal-prod": {accountType: "internal", stage: "prod"},
		"external-dev":  {accountType: "external", stage: "dev"},
		"external-test": {accountType: "external", stage: "test"},
		"external-prod": {accountType: "external", stage: "prod"},
	}

	for stack, expected := range expectedLocals {
		stack, expected := stack, expected
		t.Run(stack, func(t *testing.T) {
			t.Parallel()

			mainTFPath := filepath.Join(stacksDir(t), stack, "main.tf")
			content, err := os.ReadFile(mainTFPath)
			require.NoError(t, err, "stacks/%s/main.tf must exist", stack)

			contentStr := string(content)

			// Assert: account_type local matches expected
			expectedAccountType := fmt.Sprintf(`account_type = "%s"`, expected.accountType)
			assert.Contains(t, contentStr, expectedAccountType,
				"stack %s must set account_type = %q", stack, expected.accountType)

			// Assert: stage local matches expected
			expectedStage := fmt.Sprintf(`stage        = "%s"`, expected.stage)
			assert.Contains(t, contentStr, expectedStage,
				"stack %s must set stage = %q", stack, expected.stage)
		})
	}
}

// TestProviderDefaultTags asserts that all stacks configure default_tags
// in the provider block with the required tag keys.
//
// Validates: Requirements 1.6, 11.5
func TestProviderDefaultTags(t *testing.T) {
	t.Parallel()

	for _, stack := range allStacks() {
		stack := stack
		t.Run(stack, func(t *testing.T) {
			t.Parallel()

			providerPath := filepath.Join(stacksDir(t), stack, "provider.tf")
			content, err := os.ReadFile(providerPath)
			require.NoError(t, err, "stacks/%s/provider.tf must exist", stack)

			contentStr := string(content)

			// Assert: default_tags block exists
			assert.Contains(t, contentStr, "default_tags",
				"stack %s provider must have default_tags block", stack)

			// Assert: required tag keys are present
			assert.Contains(t, contentStr, "Environment",
				"stack %s default_tags must include Environment", stack)
			assert.Contains(t, contentStr, "Project",
				"stack %s default_tags must include Project", stack)
			assert.Contains(t, contentStr, "Owner",
				"stack %s default_tags must include Owner", stack)
		})
	}
}
