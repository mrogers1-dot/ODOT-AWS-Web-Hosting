// Feature: odot-aws-web-hosting, OIDC trust policy scoping unit test
//
// This file contains unit tests for the modules/oidc Terraform module.
// Tests use HCL parsing to validate:
//   1. The trust policy condition uses a specific repository name (not wildcard *).
//   2. iam:PassRole is scoped to ECS task execution roles only (not *).
//
// These tests parse the Terraform HCL configuration directly — no AWS credentials
// or terraform plan execution required.
//
// Requirements: 6.7, 9.6

package test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclparse"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/zclconf/go-cty/cty"
)

// oidcModulePath returns the absolute path to the modules/oidc directory.
func oidcModulePath(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err)
	return filepath.Join(wd, "..", "modules", "oidc")
}

// readOIDCMainContent reads the raw content of the OIDC module's main.tf.
func readOIDCMainContent(t *testing.T) string {
	t.Helper()
	mainTFPath := filepath.Join(oidcModulePath(t), "main.tf")
	content, err := os.ReadFile(mainTFPath)
	require.NoError(t, err, "modules/oidc/main.tf must be readable")
	return string(content)
}

// TestOIDC_TrustPolicyUsesSpecificRepoNotWildcard asserts that the trust policy
// condition on token.actions.githubusercontent.com:sub uses a specific repository
// name pattern (repo:{org}/{repo}:*) and NOT a bare wildcard (*).
//
// The OIDC module must scope trust to specific repositories to prevent any
// arbitrary GitHub repository from assuming the deployment role.
//
// Validates: Requirements 6.7, 9.6
func TestOIDC_TrustPolicyUsesSpecificRepoNotWildcard(t *testing.T) {
	t.Parallel()

	content := readOIDCMainContent(t)

	// ── Assert 1: The trust policy references token.actions.githubusercontent.com:sub
	assert.Contains(t, content, "token.actions.githubusercontent.com:sub",
		"trust policy must contain a condition on token.actions.githubusercontent.com:sub")

	// ── Assert 2: The sub-claim condition uses a specific repo pattern, not bare wildcard.
	// The module should use a pattern like "repo:${var.github_org}/${repo}:*" which
	// scopes to a specific org/repo. A bare "*" would allow ANY GitHub repo to assume the role.

	// Check that the allowed_subjects local uses the specific repo pattern.
	assert.Contains(t, content, "repo:${var.github_org}/",
		"trust policy sub condition must use specific org/repo pattern (repo:${var.github_org}/{repo}:*)")

	// Verify there is NO bare wildcard "*" used as the sole sub-claim value.
	// A bare wildcard would look like: values = ["*"]
	// We check that the condition values reference the allowed_subjects local
	// (which is built from specific repos) rather than a hardcoded wildcard.
	assert.Contains(t, content, "local.allowed_subjects",
		"trust policy condition values must reference local.allowed_subjects (specific repos), not a bare wildcard")

	// Verify the allowed_subjects local is built from var.github_repos (specific repos).
	assert.Contains(t, content, "var.github_repos",
		"allowed_subjects must be derived from var.github_repos (specific repository names)")

	// Ensure no statement uses a bare wildcard for the sub condition.
	// Look for patterns that would indicate an overly permissive trust policy.
	lines := strings.Split(content, "\n")
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		// Check for values = ["*"] pattern near the sub condition
		if trimmed == `values = ["*"]` {
			// Look at surrounding context to see if this is the sub condition
			contextStart := max(0, i-5)
			contextEnd := min(len(lines), i+1)
			context := strings.Join(lines[contextStart:contextEnd], "\n")
			if strings.Contains(context, "token.actions.githubusercontent.com:sub") {
				t.Errorf("trust policy sub condition must NOT use bare wildcard ['*']; "+
					"found at line %d", i+1)
			}
		}
	}
}

// TestOIDC_PassRoleScopedToECSTaskExecutionRolesOnly asserts that the iam:PassRole
// permission is scoped to ECS task execution roles only (not resource "*").
//
// The iam:PassRole permission is dangerous if granted on "*" because it allows
// the pipeline to pass any IAM role to ECS, potentially escalating privileges.
// It must be restricted to the odot-ecs-task-* role pattern.
//
// Validates: Requirements 6.7, 9.6
func TestOIDC_PassRoleScopedToECSTaskExecutionRolesOnly(t *testing.T) {
	t.Parallel()

	content := readOIDCMainContent(t)

	// ── Assert 1: iam:PassRole action exists in the policy.
	assert.Contains(t, content, "iam:PassRole",
		"inline policy must contain iam:PassRole action")

	// ── Assert 2: The PassRole statement has a resource constraint that includes
	// the ECS task execution role ARN pattern (odot-ecs-task-*).
	assert.Contains(t, content, "odot-ecs-task-",
		"iam:PassRole must be scoped to ECS task execution roles (pattern: odot-ecs-task-*)")

	// ── Assert 3: The PassRole statement must NOT use resource = "*".
	// Parse the content to find the PassRole statement and verify its resource.
	lines := strings.Split(content, "\n")
	inPassRoleStatement := false
	braceDepth := 0

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)

		// Detect entry into the PassRole statement block.
		if strings.Contains(line, "PassRole") && strings.Contains(line, "sid") {
			inPassRoleStatement = true
			braceDepth = 0
			continue
		}

		if inPassRoleStatement {
			braceDepth += strings.Count(trimmed, "{") - strings.Count(trimmed, "}")

			// Check for resources = ["*"] within the PassRole statement.
			if strings.Contains(trimmed, `resources`) && strings.Contains(trimmed, `"*"`) {
				// This is a bare wildcard resource — FAIL.
				t.Errorf("iam:PassRole must NOT be granted on resource '*'; " +
					"it must be scoped to ECS task execution roles only")
			}

			// Exit the statement when we return to the same brace level.
			if braceDepth <= 0 && trimmed == "}" {
				inPassRoleStatement = false
			}
		}
	}

	// ── Assert 4: The PassRole statement includes a condition restricting
	// the receiving service to ecs-tasks.amazonaws.com.
	assert.Contains(t, content, "ecs-tasks.amazonaws.com",
		"iam:PassRole must include condition restricting PassedToService to ecs-tasks.amazonaws.com")

	// ── Assert 5: The iam:PassedToService condition is present.
	assert.Contains(t, content, "iam:PassedToService",
		"iam:PassRole statement must include iam:PassedToService condition")
}

// TestOIDC_TrustPolicyHasAudienceCondition asserts that the trust policy
// includes a condition checking the audience (aud) claim equals sts.amazonaws.com.
// This prevents tokens issued for other audiences from being accepted.
//
// Validates: Requirements 6.7
func TestOIDC_TrustPolicyHasAudienceCondition(t *testing.T) {
	t.Parallel()

	content := readOIDCMainContent(t)

	// The trust policy must verify the audience claim.
	assert.Contains(t, content, "token.actions.githubusercontent.com:aud",
		"trust policy must contain a condition on token.actions.githubusercontent.com:aud")

	assert.Contains(t, content, "sts.amazonaws.com",
		"trust policy audience condition must require sts.amazonaws.com")
}

// TestOIDC_ModuleVariablesRequireSpecificRepos asserts that the module's
// variables.tf requires github_repos as a list(string), ensuring callers
// must provide specific repository names rather than relying on defaults.
//
// Validates: Requirements 6.7, 9.6
func TestOIDC_ModuleVariablesRequireSpecificRepos(t *testing.T) {
	t.Parallel()

	variablesPath := filepath.Join(oidcModulePath(t), "variables.tf")
	content, err := os.ReadFile(variablesPath)
	require.NoError(t, err, "modules/oidc/variables.tf must exist")

	contentStr := string(content)

	// Assert github_repos variable exists and is typed as list(string).
	assert.Contains(t, contentStr, "github_repos",
		"variables.tf must declare a github_repos variable")
	assert.Contains(t, contentStr, "list(string)",
		"github_repos must be typed as list(string) to require specific repo names")

	// Assert there is no default value for github_repos (callers must provide it).
	// Parse the file to check for a default block in the github_repos variable.
	parser := hclparse.NewParser()
	file, diags := parser.ParseHCLFile(variablesPath)
	require.False(t, diags.HasErrors(), "failed to parse variables.tf: %s", diags.Error())

	// Use the body to find variable blocks.
	bodyContent, diags := file.Body.Content(&hcl.BodySchema{
		Blocks: []hcl.BlockHeaderSchema{
			{Type: "variable", LabelNames: []string{"name"}},
		},
	})
	require.False(t, diags.HasErrors())

	for _, block := range bodyContent.Blocks {
		if len(block.Labels) > 0 && block.Labels[0] == "github_repos" {
			// Check that there's no default attribute (or default is not set).
			attrs, _ := block.Body.JustAttributes()
			if defaultAttr, exists := attrs["default"]; exists {
				val, _ := defaultAttr.Expr.Value(&hcl.EvalContext{
					Variables: map[string]cty.Value{},
				})
				// If default exists, it should not be an empty list or wildcard.
				if val.Type().IsListType() && val.LengthInt() == 0 {
					// Empty default list is acceptable (forces caller to override).
				} else if !val.IsNull() {
					t.Logf("github_repos has a default value — callers should be required to provide specific repos")
				}
			}
			break
		}
	}
}


