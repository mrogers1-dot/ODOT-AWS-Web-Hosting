// Feature: odot-aws-web-hosting, Networking module unit tests
//
// This file contains unit tests for the modules/networking Terraform module.
// Tests assert:
//   1. account_type = "internal" → 0 public subnets, 0 internet gateways in the plan.
//   2. account_type = "external" → ≥ 2 public subnets, exactly 1 internet gateway in the plan.
//
// Tests operate on terraform plan JSON output — no AWS credentials are required.
//
// Validates: Requirements 2.3, 3.1, 3.2

package test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// planNetworkingModule runs terraform init+plan on the networking fixture with
// the given variables and returns the plan struct for assertion.
// Each call copies the fixture to a temp directory to avoid parallel test conflicts.
// Note: networkingModuleDir is declared in internal_vpc_test.go (shared helper).
func planNetworkingModule(t *testing.T, vars map[string]interface{}) *terraform.PlanStruct {
	t.Helper()

	// Copy the fixture to a temp directory so parallel tests don't conflict
	// on the .terraform directory and lock files.
	tempDir := t.TempDir()
	copyFixtureToTemp(t, networkingModuleDir(t), tempDir)

	opts := &terraform.Options{
		TerraformDir: tempDir,
		Vars:         vars,
		PlanFilePath: filepath.Join(t.TempDir(), "plan.out"),
		NoColor:      true,
	}

	planStruct := terraform.InitAndPlanAndShowWithStructNoLogTempPlanFile(t, opts)
	require.NotNil(t, planStruct, "terraform plan output must not be nil")
	return planStruct
}

// copyFixtureToTemp copies the fixture main.tf to a temp directory and resolves
// the module source path to be absolute (since the temp dir is in a different location).
func copyFixtureToTemp(t *testing.T, fixtureDir, tempDir string) {
	t.Helper()

	// Read the fixture main.tf
	content, err := os.ReadFile(filepath.Join(fixtureDir, "main.tf"))
	require.NoError(t, err, "failed to read fixture main.tf")

	// Resolve the relative module source to an absolute path
	modulesDir := filepath.Join(fixtureDir, "..", "..", "..", "modules", "networking")
	absModulesDir, err := filepath.Abs(modulesDir)
	require.NoError(t, err, "failed to resolve absolute module path")

	// Replace the relative source with the absolute path
	contentStr := strings.Replace(string(content),
		`source = "../../../modules/networking"`,
		fmt.Sprintf(`source = "%s"`, absModulesDir),
		1)

	err = os.WriteFile(filepath.Join(tempDir, "main.tf"), []byte(contentStr), 0644)
	require.NoError(t, err, "failed to write temp main.tf")
}

// countResourcesByType counts the number of planned resource changes of a given
// type (e.g., "aws_subnet", "aws_internet_gateway") in the plan.
func countResourcesByType(plan *terraform.PlanStruct, resourceType string) int {
	count := 0
	for _, rc := range plan.RawPlan.ResourceChanges {
		if rc.Type == resourceType && !isNoOpAction(rc.Change.Actions) {
			count++
		}
	}
	return count
}

// countPublicSubnets counts subnets in the plan that have map_public_ip_on_launch = true.
func countPublicSubnets(t *testing.T, plan *terraform.PlanStruct) int {
	t.Helper()
	count := 0
	for _, rc := range plan.RawPlan.ResourceChanges {
		if rc.Type != "aws_subnet" || isNoOpAction(rc.Change.Actions) {
			continue
		}
		// Check the planned "after" values for map_public_ip_on_launch
		if rc.Change.After != nil {
			afterMap, ok := rc.Change.After.(map[string]interface{})
			if ok {
				if mapPublicIP, exists := afterMap["map_public_ip_on_launch"]; exists {
					if val, ok := mapPublicIP.(bool); ok && val {
						count++
					}
				}
			}
		}
	}
	return count
}

// countResourcesByTypeAndAddress counts resources matching both a type and an
// address substring pattern.
func countResourcesByTypeAndAddress(plan *terraform.PlanStruct, resourceType, addressContains string) int {
	count := 0
	for _, rc := range plan.RawPlan.ResourceChanges {
		if rc.Type == resourceType && !isNoOpAction(rc.Change.Actions) {
			if strings.Contains(rc.Address, addressContains) {
				count++
			}
		}
	}
	return count
}

// ── Tests ─────────────────────────────────────────────────────────────────────

// TestNetworkingInternalAccountNoPublicSubnetsNoIGW asserts that when
// account_type = "internal", the terraform plan produces:
//   - 0 public subnets (no aws_subnet with map_public_ip_on_launch = true)
//   - 0 internet gateways (no aws_internet_gateway resource)
//
// This validates that internal VPCs are completely private with no path to
// the public internet.
//
// Validates: Requirements 2.3
func TestNetworkingInternalAccountNoPublicSubnetsNoIGW(t *testing.T) {
	t.Parallel()

	vars := map[string]interface{}{
		"account_type":       "internal",
		"stage":              "dev",
		"vpc_cidr":           "10.0.0.0/16",
		"availability_zones": []string{"us-east-2a", "us-east-2b"},
		"tags": map[string]string{
			"Environment": "dev",
			"Project":     "ODOTWebHosting",
			"Owner":       "odot-platform-team",
		},
	}

	plan := planNetworkingModule(t, vars)

	// Assert: 0 internet gateways in the plan.
	igwCount := countResourcesByType(plan, "aws_internet_gateway")
	assert.Equal(t, 0, igwCount,
		"internal account must have 0 internet gateways; got %d", igwCount)

	// Assert: 0 public subnets (no subnet with map_public_ip_on_launch = true).
	publicSubnetCount := countPublicSubnets(t, plan)
	assert.Equal(t, 0, publicSubnetCount,
		"internal account must have 0 public subnets (map_public_ip_on_launch = true); got %d", publicSubnetCount)

	// Assert: 0 aws_subnet resources with "public" in the address.
	publicSubnetResourceCount := countResourcesByTypeAndAddress(plan, "aws_subnet", "public")
	assert.Equal(t, 0, publicSubnetResourceCount,
		"internal account must have 0 public subnet resources; got %d", publicSubnetResourceCount)
}

// TestNetworkingExternalAccountHasPublicSubnetsAndIGW asserts that when
// account_type = "external", the terraform plan produces:
//   - ≥ 2 public subnets (one per AZ, with map_public_ip_on_launch = true)
//   - Exactly 1 internet gateway
//
// This validates that external VPCs have the required public-facing
// infrastructure for ALBs.
//
// Validates: Requirements 3.1, 3.2
func TestNetworkingExternalAccountHasPublicSubnetsAndIGW(t *testing.T) {
	t.Parallel()

	vars := map[string]interface{}{
		"account_type":       "external",
		"stage":              "prod",
		"vpc_cidr":           "10.1.0.0/16",
		"availability_zones": []string{"us-east-2a", "us-east-2b"},
		"tags": map[string]string{
			"Environment": "prod",
			"Project":     "ODOTWebHosting",
			"Owner":       "odot-platform-team",
		},
	}

	plan := planNetworkingModule(t, vars)

	// Assert: exactly 1 internet gateway in the plan.
	igwCount := countResourcesByType(plan, "aws_internet_gateway")
	assert.Equal(t, 1, igwCount,
		"external account must have exactly 1 internet gateway; got %d", igwCount)

	// Assert: ≥ 2 public subnets (one per AZ).
	publicSubnetCount := countPublicSubnets(t, plan)
	assert.GreaterOrEqual(t, publicSubnetCount, 2,
		"external account must have >= 2 public subnets; got %d", publicSubnetCount)

	// Assert: public subnet resources exist in the plan.
	publicSubnetResourceCount := countResourcesByTypeAndAddress(plan, "aws_subnet", "public")
	assert.GreaterOrEqual(t, publicSubnetResourceCount, 2,
		"external account must have >= 2 public subnet resources; got %d", publicSubnetResourceCount)
}

// TestNetworkingExternalAccountThreeAZs asserts that when 3 AZs are provided
// for an external account, the plan produces 3 public subnets and still
// exactly 1 internet gateway.
//
// Validates: Requirements 3.1, 3.2
func TestNetworkingExternalAccountThreeAZs(t *testing.T) {
	t.Parallel()

	vars := map[string]interface{}{
		"account_type":       "external",
		"stage":              "test",
		"vpc_cidr":           "10.2.0.0/16",
		"availability_zones": []string{"us-east-2a", "us-east-2b", "us-east-2c"},
		"tags": map[string]string{
			"Environment": "test",
			"Project":     "ODOTWebHosting",
			"Owner":       "odot-platform-team",
		},
	}

	plan := planNetworkingModule(t, vars)

	// Assert: exactly 1 internet gateway regardless of AZ count.
	igwCount := countResourcesByType(plan, "aws_internet_gateway")
	assert.Equal(t, 1, igwCount,
		"external account must have exactly 1 internet gateway; got %d", igwCount)

	// Assert: 3 public subnets (one per AZ).
	publicSubnetCount := countPublicSubnets(t, plan)
	assert.Equal(t, 3, publicSubnetCount,
		"external account with 3 AZs must have 3 public subnets; got %d", publicSubnetCount)
}

// TestNetworkingInternalAccountMultipleStages asserts that the internal account
// produces 0 public subnets and 0 IGW regardless of the stage value.
//
// Validates: Requirements 2.3
func TestNetworkingInternalAccountMultipleStages(t *testing.T) {
	t.Parallel()

	stages := []string{"dev", "test", "prod"}

	for _, stage := range stages {
		stage := stage // capture loop variable
		t.Run(stage, func(t *testing.T) {
			t.Parallel()

			vars := map[string]interface{}{
				"account_type":       "internal",
				"stage":              stage,
				"vpc_cidr":           "10.0.0.0/16",
				"availability_zones": []string{"us-east-2a", "us-east-2b"},
				"tags": map[string]string{
					"Environment": stage,
					"Project":     "ODOTWebHosting",
					"Owner":       "odot-platform-team",
				},
			}

			plan := planNetworkingModule(t, vars)

			// Assert: 0 internet gateways for all stages.
			igwCount := countResourcesByType(plan, "aws_internet_gateway")
			assert.Equal(t, 0, igwCount,
				"internal account (%s) must have 0 internet gateways; got %d", stage, igwCount)

			// Assert: 0 public subnets for all stages.
			publicSubnetCount := countPublicSubnets(t, plan)
			assert.Equal(t, 0, publicSubnetCount,
				"internal account (%s) must have 0 public subnets; got %d", stage, publicSubnetCount)
		})
	}
}
