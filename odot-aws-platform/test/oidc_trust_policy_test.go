// Feature: odot-aws-web-hosting, OIDC trust policy scoping unit test
//
// This file contains plan-based unit tests for the modules/oidc Terraform module.
// Tests assert:
//   1. The trust policy condition uses the specific repository name, not a wildcard (*).
//   2. iam:PassRole is scoped to ECS task execution roles only (not *).
//
// These tests require valid AWS credentials to run terraform plan (the AWS provider
// resolves data sources during planning). They are skipped when AWS_REGION is not set
// or credentials are unavailable. The equivalent HCL-parsing tests in oidc_test.go
// provide the same coverage without credentials.
//
// Requirements: 6.7, 9.6

package test

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// skipIfNoAWSCredentials skips the test if AWS credentials are not available.
// Plan-based tests require the AWS provider to call sts:GetCallerIdentity.
func skipIfNoAWSCredentials(t *testing.T) {
	t.Helper()
	cmd := exec.Command("aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text")
	if err := cmd.Run(); err != nil {
		t.Skip("Skipping plan-based test: AWS credentials not available. " +
			"Equivalent HCL-parsing tests in oidc_test.go provide coverage without credentials.")
	}
}

// iamPolicyDocument mirrors the structure of an IAM policy document JSON.
type iamPolicyDocument struct {
	Version   string       `json:"Version"`
	Statement []iamStatement `json:"Statement"`
}

type iamStatement struct {
	Sid       string                 `json:"Sid"`
	Effect    string                 `json:"Effect"`
	Action    interface{}            `json:"Action"`   // string or []string
	Resource  interface{}            `json:"Resource"` // string or []string
	Principal map[string]interface{} `json:"Principal"`
	Condition map[string]map[string]interface{} `json:"Condition"`
}

// actions returns the statement's Action field as a []string regardless of
// whether the original JSON encoded it as a string or an array.
func (s iamStatement) actions() []string {
	switch v := s.Action.(type) {
	case string:
		return []string{v}
	case []interface{}:
		out := make([]string, 0, len(v))
		for _, a := range v {
			if str, ok := a.(string); ok {
				out = append(out, str)
			}
		}
		return out
	}
	return nil
}

// resources returns the statement's Resource field as a []string.
func (s iamStatement) resources() []string {
	switch v := s.Resource.(type) {
	case string:
		return []string{v}
	case []interface{}:
		out := make([]string, 0, len(v))
		for _, r := range v {
			if str, ok := r.(string); ok {
				out = append(out, str)
			}
		}
		return out
	}
	return nil
}

// conditionValues returns all values for a given condition operator + key pair.
func (s iamStatement) conditionValues(operator, key string) []string {
	if s.Condition == nil {
		return nil
	}
	opMap, ok := s.Condition[operator]
	if !ok {
		return nil
	}
	raw, ok := opMap[key]
	if !ok {
		return nil
	}
	switch v := raw.(type) {
	case string:
		return []string{v}
	case []interface{}:
		out := make([]string, 0, len(v))
		for _, item := range v {
			if str, ok := item.(string); ok {
				out = append(out, str)
			}
		}
		return out
	}
	return nil
}

// ── Helpers ──────────────────────────────────────────────────────────────────

// moduleDir returns the absolute path to modules/oidc relative to this test file.
func moduleDir(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err, "could not determine working directory")
	return filepath.Join(wd, "..", "modules", "oidc")
}

// planAndGetResources runs terraform plan on the oidc module with the supplied
// variables and returns the planned resource_changes map keyed by address.
func planAndGetResources(t *testing.T, vars map[string]interface{}) map[string]json.RawMessage {
	t.Helper()

	opts := &terraform.Options{
		TerraformDir: moduleDir(t),
		Vars:         vars,
		PlanFilePath: filepath.Join(t.TempDir(), "plan.out"),
		NoColor:      true,
	}

	planJSON := terraform.InitAndPlanAndShowWithStructNoLogTempPlanFile(t, opts)
	require.NotNil(t, planJSON, "terraform plan output must not be nil")

	// Index resource changes by their address for easy lookup.
	resources := make(map[string]json.RawMessage)
	for _, rc := range planJSON.RawPlan.ResourceChanges {
		if isNoOpAction(rc.Change.Actions) {
			continue
		}
		raw, err := json.Marshal(rc.Change.After)
		require.NoError(t, err)
		resources[rc.Address] = raw
	}
	return resources
}

// parsePolicy unmarshals a JSON-encoded IAM policy document string.
func parsePolicy(t *testing.T, raw string) iamPolicyDocument {
	t.Helper()
	var doc iamPolicyDocument
	require.NoError(t, json.Unmarshal([]byte(raw), &doc),
		"failed to parse IAM policy document JSON")
	return doc
}

// ── Tests ─────────────────────────────────────────────────────────────────────

// TestOIDCTrustPolicyUsesSpecificRepo asserts that the trust policy condition
// on token.actions.githubusercontent.com:sub uses the specific repository name
// (repo:{org}/{repo}:*) and NOT a bare wildcard (*).
//
// Validates: Requirements 6.7, 9.6
func TestOIDCTrustPolicyUsesSpecificRepo(t *testing.T) {
	t.Parallel()
	skipIfNoAWSCredentials(t)

	const (
		testOrg      = "odot-ohio"
		testRepo     = "my-test-app"
		testAccount  = "123456789012"
		testAcctType = "internal"
	)

	vars := map[string]interface{}{
		"github_org":   testOrg,
		"github_repos": []string{testRepo},
		"account_id":   testAccount,
		"account_type": testAcctType,
		"tags": map[string]string{
			"Environment": "dev",
			"Project":     "ODOTWebHosting",
			"Owner":       "odot-platform-team",
		},
	}

	resources := planAndGetResources(t, vars)

	// Locate the IAM role resource in the plan.
	roleKey := "aws_iam_role.github_actions"
	roleRaw, ok := resources[roleKey]
	require.True(t, ok, "expected resource %q in plan", roleKey)

	// Extract the assume_role_policy field from the planned role attributes.
	var roleAttrs struct {
		AssumeRolePolicy string `json:"assume_role_policy"`
	}
	require.NoError(t, json.Unmarshal(roleRaw, &roleAttrs))
	require.NotEmpty(t, roleAttrs.AssumeRolePolicy, "assume_role_policy must not be empty")

	trustPolicy := parsePolicy(t, roleAttrs.AssumeRolePolicy)

	// Find the statement that contains the sub-claim condition.
	var subConditionValues []string
	for _, stmt := range trustPolicy.Statement {
		// Check both StringLike and StringEquals operators (module uses StringLike).
		for _, op := range []string{"StringLike", "StringEquals"} {
			vals := stmt.conditionValues(op, "token.actions.githubusercontent.com:sub")
			if len(vals) > 0 {
				subConditionValues = append(subConditionValues, vals...)
			}
		}
	}

	require.NotEmpty(t, subConditionValues,
		"trust policy must contain a condition on token.actions.githubusercontent.com:sub")

	// Assert 1: No value is a bare wildcard (*).
	for _, v := range subConditionValues {
		assert.NotEqual(t, "*", v,
			"trust policy sub condition must not be a bare wildcard (*); got %q", v)
	}

	// Assert 2: At least one value encodes the specific org and repo name.
	expectedPattern := "repo:" + testOrg + "/" + testRepo + ":"
	found := false
	for _, v := range subConditionValues {
		if strings.HasPrefix(v, expectedPattern) {
			found = true
			break
		}
	}
	assert.True(t, found,
		"trust policy sub condition must contain a value starting with %q; got %v",
		expectedPattern, subConditionValues)
}

// TestOIDCTrustPolicyMultipleRepos asserts that when multiple repos are supplied,
// each repo gets its own scoped sub-claim pattern (not a single wildcard).
//
// Validates: Requirements 6.7, 9.6
func TestOIDCTrustPolicyMultipleRepos(t *testing.T) {
	t.Parallel()
	skipIfNoAWSCredentials(t)

	const (
		testOrg      = "odot-ohio"
		testAccount  = "123456789012"
		testAcctType = "external"
	)
	testRepos := []string{"app-one", "app-two"}

	vars := map[string]interface{}{
		"github_org":   testOrg,
		"github_repos": testRepos,
		"account_id":   testAccount,
		"account_type": testAcctType,
		"tags": map[string]string{
			"Environment": "prod",
			"Project":     "ODOTWebHosting",
			"Owner":       "odot-platform-team",
		},
	}

	resources := planAndGetResources(t, vars)

	roleKey := "aws_iam_role.github_actions"
	roleRaw, ok := resources[roleKey]
	require.True(t, ok, "expected resource %q in plan", roleKey)

	var roleAttrs struct {
		AssumeRolePolicy string `json:"assume_role_policy"`
	}
	require.NoError(t, json.Unmarshal(roleRaw, &roleAttrs))

	trustPolicy := parsePolicy(t, roleAttrs.AssumeRolePolicy)

	var subConditionValues []string
	for _, stmt := range trustPolicy.Statement {
		for _, op := range []string{"StringLike", "StringEquals"} {
			vals := stmt.conditionValues(op, "token.actions.githubusercontent.com:sub")
			subConditionValues = append(subConditionValues, vals...)
		}
	}

	require.NotEmpty(t, subConditionValues)

	// Each repo must have its own scoped entry; no bare wildcard allowed.
	for _, v := range subConditionValues {
		assert.NotEqual(t, "*", v,
			"trust policy sub condition must not be a bare wildcard (*); got %q", v)
	}

	// Both repos must appear in the condition values.
	for _, repo := range testRepos {
		expectedPrefix := "repo:" + testOrg + "/" + repo + ":"
		found := false
		for _, v := range subConditionValues {
			if strings.HasPrefix(v, expectedPrefix) {
				found = true
				break
			}
		}
		assert.True(t, found,
			"trust policy must contain a sub condition value starting with %q; got %v",
			expectedPrefix, subConditionValues)
	}
}

// TestPassRoleScopedToECSTaskExecutionRoles asserts that the iam:PassRole
// permission in the inline policy is NOT granted on resource "*" and IS
// restricted to the ECS task execution role ARN pattern.
//
// Validates: Requirements 6.7, 9.6
func TestPassRoleScopedToECSTaskExecutionRoles(t *testing.T) {
	t.Parallel()
	skipIfNoAWSCredentials(t)

	const (
		testOrg      = "odot-ohio"
		testRepo     = "my-test-app"
		testAccount  = "123456789012"
		testAcctType = "internal"
	)

	vars := map[string]interface{}{
		"github_org":   testOrg,
		"github_repos": []string{testRepo},
		"account_id":   testAccount,
		"account_type": testAcctType,
		"tags": map[string]string{
			"Environment": "dev",
			"Project":     "ODOTWebHosting",
			"Owner":       "odot-platform-team",
		},
	}

	resources := planAndGetResources(t, vars)

	// Locate the inline policy resource.
	policyKey := "aws_iam_role_policy.github_actions"
	policyRaw, ok := resources[policyKey]
	require.True(t, ok, "expected resource %q in plan", policyKey)

	var policyAttrs struct {
		Policy string `json:"policy"`
	}
	require.NoError(t, json.Unmarshal(policyRaw, &policyAttrs))
	require.NotEmpty(t, policyAttrs.Policy, "inline policy document must not be empty")

	inlinePolicy := parsePolicy(t, policyAttrs.Policy)

	// Find the statement(s) that grant iam:PassRole.
	var passRoleStatements []iamStatement
	for _, stmt := range inlinePolicy.Statement {
		for _, action := range stmt.actions() {
			if strings.EqualFold(action, "iam:PassRole") {
				passRoleStatements = append(passRoleStatements, stmt)
				break
			}
		}
	}

	require.NotEmpty(t, passRoleStatements,
		"inline policy must contain at least one statement granting iam:PassRole")

	for _, stmt := range passRoleStatements {
		resources := stmt.resources()

		// Assert: iam:PassRole must NOT be granted on "*".
		for _, r := range resources {
			assert.NotEqual(t, "*", r,
				"iam:PassRole must not be granted on resource '*'; got %q", r)
		}

		// Assert: every resource ARN must match the ECS task execution role pattern.
		// Expected pattern: arn:aws:iam::{account}:role/odot-ecs-task-*
		for _, r := range resources {
			assert.True(t,
				strings.Contains(r, ":role/odot-ecs-task-"),
				"iam:PassRole resource must be scoped to ECS task execution roles "+
					"(pattern :role/odot-ecs-task-*); got %q", r)
		}

		// Assert: the PassRole statement must include a condition restricting
		// the receiving service to ecs-tasks.amazonaws.com.
		passedToService := stmt.conditionValues("StringEquals", "iam:PassedToService")
		assert.Contains(t, passedToService, "ecs-tasks.amazonaws.com",
			"iam:PassRole statement must include condition iam:PassedToService = ecs-tasks.amazonaws.com")
	}
}

// TestOIDCRoleNameFollowsNamingConvention asserts that the IAM role is named
// odot-github-actions-{account_type} per the design naming convention.
//
// Validates: Requirements 13.1
func TestOIDCRoleNameFollowsNamingConvention(t *testing.T) {
	t.Parallel()
	skipIfNoAWSCredentials(t)

	for _, acctType := range []string{"internal", "external"} {
		acctType := acctType // capture loop variable
		t.Run(acctType, func(t *testing.T) {
			t.Parallel()

			vars := map[string]interface{}{
				"github_org":   "odot-ohio",
				"github_repos": []string{"some-app"},
				"account_id":   "123456789012",
				"account_type": acctType,
				"tags": map[string]string{
					"Environment": "dev",
					"Project":     "ODOTWebHosting",
					"Owner":       "odot-platform-team",
				},
			}

			resources := planAndGetResources(t, vars)

			roleKey := "aws_iam_role.github_actions"
			roleRaw, ok := resources[roleKey]
			require.True(t, ok, "expected resource %q in plan", roleKey)

			var roleAttrs struct {
				Name string `json:"name"`
			}
			require.NoError(t, json.Unmarshal(roleRaw, &roleAttrs))

			expectedName := "odot-github-actions-" + acctType
			assert.Equal(t, expectedName, roleAttrs.Name,
				"IAM role name must follow the convention odot-github-actions-{account_type}")
		})
	}
}
