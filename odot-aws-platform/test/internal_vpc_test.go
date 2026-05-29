// Feature: odot-aws-web-hosting, Property 12
//
// Property 12: Internal-account VPC configurations contain no internet gateway.
//
// For any networking module configuration where account_type = "internal",
// the rendered Terraform plan SHALL contain no aws_internet_gateway resource
// and no subnet resource with map_public_ip_on_launch = true.
//
// This test uses the rapid library to generate random valid vpc_cidr and
// availability_zones inputs, runs terraform plan on the networking module,
// and asserts the property holds across all generated configurations.
//
// Tests operate on terraform plan JSON output — no AWS credentials are required.
//
// Validates: Requirements 2.3

package test

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
	"pgregory.net/rapid"
)

// networkingModuleDir returns the absolute path to the networking test fixture
// which wraps modules/networking with a mock provider (skip_credentials_validation = true).
// This allows terraform plan to run without real AWS credentials.
func networkingModuleDir(t testing.TB) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err, "could not determine working directory")
	return filepath.Join(wd, "fixtures", "networking")
}

// availableAZs is the pool of valid us-east-2 Availability Zones used for
// generating random AZ lists. The networking module requires a minimum of 2.
var availableAZs = []string{
	"us-east-2a",
	"us-east-2b",
	"us-east-2c",
}

// TestProperty12_InternalVPCNoInternetGateway is a property-based test that
// asserts: for any valid vpc_cidr and availability_zones combination, an
// internal-account networking module plan contains no aws_internet_gateway
// resource and no subnet with map_public_ip_on_launch = true.
//
// **Validates: Requirements 2.3**
func TestProperty12_InternalVPCNoInternetGateway(t *testing.T) {
	t.Parallel()

	rapid.Check(t, func(rt *rapid.T) {
		// Generate a random valid VPC CIDR in the 10.x.0.0/16 range.
		// The second octet is randomized to produce diverse CIDR blocks.
		secondOctet := rapid.IntRange(0, 255).Draw(rt, "cidr_second_octet")
		vpcCIDR := fmt.Sprintf("10.%d.0.0/16", secondOctet)

		// Generate a random subset of availability zones (minimum 2, maximum 3).
		azCount := rapid.IntRange(2, 3).Draw(rt, "az_count")
		azs := availableAZs[:azCount]

		// Pick a random stage — the property must hold for all stages.
		stage := rapid.SampledFrom([]string{"dev", "test", "prod"}).Draw(rt, "stage")

		// Tags required by the module
		tags := map[string]string{
			"Environment": stage,
			"Project":     "ODOTWebHosting",
			"Owner":       "odot-platform-team",
		}

		// Configure terraform options for the networking module with internal account type
		vars := map[string]interface{}{
			"account_type":       "internal",
			"stage":              stage,
			"vpc_cidr":           vpcCIDR,
			"availability_zones": azs,
			"tags":               tags,
		}

		// Create a temporary directory and copy the fixture to avoid parallel conflicts
		planDir := filepath.Join(os.TempDir(), fmt.Sprintf("tf-plan-internal-vpc-%d-%s-%d", secondOctet, stage, azCount))
		os.MkdirAll(planDir, 0755)
		defer os.RemoveAll(planDir)

		// Copy fixture to temp dir with absolute module source path
		fixtureDir := networkingModuleDir(t)
		modulesDir := filepath.Join(fixtureDir, "..", "..", "..", "modules", "networking")
		absModulesDir, err := filepath.Abs(modulesDir)
		require.NoError(t, err, "failed to resolve absolute module path")

		fixtureContent, err := os.ReadFile(filepath.Join(fixtureDir, "main.tf"))
		require.NoError(t, err, "failed to read fixture main.tf")

		contentStr := strings.Replace(string(fixtureContent),
			`source = "../../../modules/networking"`,
			fmt.Sprintf(`source = "%s"`, absModulesDir),
			1)
		err = os.WriteFile(filepath.Join(planDir, "main.tf"), []byte(contentStr), 0644)
		require.NoError(t, err, "failed to write temp main.tf")

		opts := &terraform.Options{
			TerraformDir: planDir,
			Vars:         vars,
			PlanFilePath: filepath.Join(planDir, "plan.out"),
			NoColor:      true,
		}

		// Run terraform init and plan, get the structured plan output
		plan := terraform.InitAndPlanAndShowWithStructNoLogTempPlanFile(t, opts)
		require.NotNil(t, plan, "terraform plan output must not be nil")

		// Iterate all planned resource changes and assert the property
		for _, rc := range plan.RawPlan.ResourceChanges {
			// Skip no-op changes and data sources
			if isNoOpAction(rc.Change.Actions) || isReadAction(rc.Change.Actions) {
				continue
			}

			// ASSERTION 1: No aws_internet_gateway resource should exist
			require.NotEqual(t, "aws_internet_gateway", rc.Type,
				"internal-account VPC must NOT contain an aws_internet_gateway resource; "+
					"found resource %s (vpc_cidr=%s, stage=%s, azs=%v)",
				rc.Address, vpcCIDR, stage, azs)

			// ASSERTION 2: No subnet should have map_public_ip_on_launch = true
			if rc.Type == "aws_subnet" {
				// Parse the planned "after" state to check map_public_ip_on_launch
				afterRaw, err := json.Marshal(rc.Change.After)
				require.NoError(t, err,
					"failed to marshal resource %s after state", rc.Address)

				var afterState map[string]interface{}
				err = json.Unmarshal(afterRaw, &afterState)
				require.NoError(t, err,
					"failed to unmarshal resource %s after state", rc.Address)

				mapPublicIP, exists := afterState["map_public_ip_on_launch"]
				if exists && mapPublicIP != nil {
					// Assert map_public_ip_on_launch is false (or not set)
					isPublic, ok := mapPublicIP.(bool)
					if ok {
						require.False(t, isPublic,
							"internal-account subnet %s must NOT have map_public_ip_on_launch = true; "+
								"found true (vpc_cidr=%s, stage=%s, azs=%v)",
							rc.Address, vpcCIDR, stage, azs)
					}
				}
			}
		}
	})
}
