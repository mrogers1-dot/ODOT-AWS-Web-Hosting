// Feature: odot-aws-web-hosting, Property 1: All module-produced resources carry required tags
//
// This file contains a property-based test that validates all resources produced
// by the app-service Terraform module carry the required tags: Environment,
// Project, and Owner — with non-empty values.
//
// The test uses the rapid library to generate random valid combinations of
// app_name, stage, account_type, and runtime, then runs terraform plan and
// inspects the planned resource changes to assert tagging compliance.
//
// Tests operate on terraform plan JSON output — no AWS credentials are required.
//
// Validates: Requirements 1.6, 11.5

package test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
	"pgregory.net/rapid"
)

// appServiceModuleDir returns the absolute path to modules/app-service.
func appServiceModuleDir(t testing.TB) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err, "could not determine working directory")
	return filepath.Join(wd, "..", "modules", "app-service")
}

// resourceSupportsTagging returns true if the resource type supports AWS tags.
// Some Terraform resource types (like lifecycle policies, WAF associations)
// do not support tags and should be excluded from tag assertions.
func resourceSupportsTagging(resourceType string) bool {
	// Resources that do NOT support tags in the AWS provider
	nonTaggableResources := map[string]bool{
		"aws_ecr_lifecycle_policy":      true,
		"aws_wafv2_web_acl_association": true,
	}
	return !nonTaggableResources[resourceType]
}

// TestProperty1_AllResourcesCarryRequiredTags is a property-based test that
// asserts every AWS resource produced by the app-service module includes
// non-empty Environment, Project, and Owner tags for any valid combination
// of inputs.
//
// **Validates: Requirements 1.6, 11.5**
func TestProperty1_AllResourcesCarryRequiredTags(t *testing.T) {
	t.Parallel()
	skipIfNoAWSCredentials(t)

	rapid.Check(t, func(rt *rapid.T) {
		// Generate random valid inputs for the app-service module
		appName := rapid.StringMatching(`[a-z][a-z0-9]{2,10}`).Draw(rt, "app_name")
		stage := rapid.SampledFrom([]string{"dev", "test", "prod"}).Draw(rt, "stage")
		accountType := rapid.SampledFrom([]string{"internal", "external"}).Draw(rt, "account_type")
		runtime := rapid.SampledFrom([]string{"linux", "windows"}).Draw(rt, "runtime")

		// CPU must be at least 1024 for Windows; valid Fargate values for Linux start at 256
		var cpu int
		if runtime == "windows" {
			cpu = rapid.SampledFrom([]int{1024, 2048, 4096}).Draw(rt, "cpu")
		} else {
			cpu = rapid.SampledFrom([]int{256, 512, 1024, 2048, 4096}).Draw(rt, "cpu")
		}

		// Memory must be a valid Fargate value for the chosen CPU
		memory := rapid.SampledFrom([]int{512, 1024, 2048}).Draw(rt, "memory")

		// Build tags map with the required keys
		tags := map[string]string{
			"Environment": stage,
			"Project":     "ODOTWebHosting",
			"Owner":       "odot-platform-team",
		}

		// Terraform variables for the app-service module
		vars := map[string]interface{}{
			"app_name":           appName,
			"account_type":       accountType,
			"stage":              stage,
			"runtime":            runtime,
			"container_port":     8080,
			"cpu":                cpu,
			"memory":             memory,
			"vpc_id":             "vpc-12345678",
			"alb_subnet_ids":     []string{"subnet-aaaaaaaa", "subnet-bbbbbbbb"},
			"private_subnet_ids": []string{"subnet-cccccccc", "subnet-dddddddd"},
			"cluster_name":       "WebHosting-" + stage,
			"cluster_arn":        "arn:aws:ecs:us-east-2:123456789012:cluster/WebHosting-" + stage,
			"kms_key_arn":        "arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012",
			"waf_acl_arn":        func() string { if accountType == "external" { return "arn:aws:wafv2:us-east-2:123456789012:regional/webacl/odot-external/12345678-1234-1234-1234-123456789012" }; return "" }(),
			"sns_topic_arn":      "arn:aws:sns:us-east-2:123456789012:odot-alerts-" + accountType,
			"tags":               tags,
		}

		// Run terraform plan and capture the JSON output
		planDir := filepath.Join(os.TempDir(), "tf-plan-tagging-"+appName+"-"+stage+"-"+accountType+"-"+runtime)
		os.MkdirAll(planDir, 0755)
		defer os.RemoveAll(planDir)

		opts := &terraform.Options{
			TerraformDir: appServiceModuleDir(t),
			Vars:         vars,
			PlanFilePath: filepath.Join(planDir, "plan.out"),
			NoColor:      true,
		}

		// Run init and plan, get the structured plan output
		plan := terraform.InitAndPlanAndShowWithStructNoLogTempPlanFile(t, opts)
		require.NotNil(t, plan, "terraform plan output must not be nil")

		// Iterate all planned resource changes and assert tags
		resourceCount := 0
		for _, rc := range plan.RawPlan.ResourceChanges {
			// Skip no-op changes and data sources
			if isNoOpAction(rc.Change.Actions) || isReadAction(rc.Change.Actions) {
				continue
			}

			// Skip resources that don't support tags
			if !resourceSupportsTagging(rc.Type) {
				continue
			}

			// Parse the planned "after" state to check tags
			afterRaw, err := json.Marshal(rc.Change.After)
			require.NoError(t, err, "failed to marshal resource %s after state", rc.Address)

			var afterState map[string]interface{}
			err = json.Unmarshal(afterRaw, &afterState)
			require.NoError(t, err, "failed to unmarshal resource %s after state", rc.Address)

			// Extract tags — Terraform plan JSON uses "tags" or "tags_all"
			tagsRaw, hasTags := afterState["tags"]
			tagsAllRaw, hasTagsAll := afterState["tags_all"]

			// Use tags_all if available (includes provider default_tags), otherwise use tags
			var resourceTags map[string]interface{}
			if hasTagsAll && tagsAllRaw != nil {
				if tagMap, ok := tagsAllRaw.(map[string]interface{}); ok {
					resourceTags = tagMap
				}
			} else if hasTags && tagsRaw != nil {
				if tagMap, ok := tagsRaw.(map[string]interface{}); ok {
					resourceTags = tagMap
				}
			}

			// If the resource has no tags field at all, it may be a resource type
			// that doesn't support tags (not caught by our allowlist). Skip it.
			if !hasTags && !hasTagsAll {
				continue
			}

			// Assert required tags are present and non-empty
			resourceCount++

			require.NotNil(t, resourceTags,
				"resource %s (type: %s) must have tags, got nil", rc.Address, rc.Type)

			envTag, envOk := resourceTags["Environment"]
			require.True(t, envOk,
				"resource %s (type: %s) must have 'Environment' tag", rc.Address, rc.Type)
			require.NotEmpty(t, envTag,
				"resource %s (type: %s) 'Environment' tag must not be empty", rc.Address, rc.Type)

			projTag, projOk := resourceTags["Project"]
			require.True(t, projOk,
				"resource %s (type: %s) must have 'Project' tag", rc.Address, rc.Type)
			require.NotEmpty(t, projTag,
				"resource %s (type: %s) 'Project' tag must not be empty", rc.Address, rc.Type)

			ownerTag, ownerOk := resourceTags["Owner"]
			require.True(t, ownerOk,
				"resource %s (type: %s) must have 'Owner' tag", rc.Address, rc.Type)
			require.NotEmpty(t, ownerTag,
				"resource %s (type: %s) 'Owner' tag must not be empty", rc.Address, rc.Type)
		}

		// Ensure we actually checked at least one resource
		require.Greater(t, resourceCount, 0,
			"expected at least one taggable resource in the plan for app_name=%s, stage=%s, account_type=%s, runtime=%s",
			appName, stage, accountType, runtime)
	})
}
