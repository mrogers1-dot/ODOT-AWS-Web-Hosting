// Feature: odot-aws-web-hosting, Property 16: Internal VPCs contain required VPC endpoints
//
// For any networking module configuration where account_type = "internal",
// the module SHALL provision 7 interface endpoints (ecr.api, ecr.dkr, logs,
// secretsmanager, ssm, ssmmessages, sts) and 1 S3 gateway endpoint.
// External VPCs SHALL contain none of these endpoints.
//
// Tests use HCL parsing — no AWS credentials required.
//
// Validates: Requirements 15.1, 15.2, 15.3

package test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestProperty16_InternalVPCEndpoints asserts that the networking module
// provisions all required VPC endpoints for internal accounts.
//
// Validates: Requirements 15.1, 15.2
func TestProperty16_InternalVPCEndpoints(t *testing.T) {
	t.Parallel()

	wd, err := os.Getwd()
	require.NoError(t, err)
	endpointsPath := filepath.Join(wd, "..", "modules", "networking", "vpc-endpoints.tf")
	content, err := os.ReadFile(endpointsPath)
	require.NoError(t, err, "modules/networking/vpc-endpoints.tf must exist")

	contentStr := string(content)

	// Assert: All 7 interface endpoint services are listed
	requiredServices := []string{
		"ecr.api", "ecr.dkr", "logs",
		"secretsmanager", "ssm", "ssmmessages", "sts",
	}
	for _, svc := range requiredServices {
		assert.Contains(t, contentStr, `"`+svc+`"`,
			"vpc-endpoints.tf must include interface endpoint for %s", svc)
	}

	// Assert: Interface endpoints are conditional on internal account
	assert.Contains(t, contentStr, "is_internal",
		"interface endpoints must be conditional on internal account type")

	// Assert: S3 gateway endpoint exists
	assert.Contains(t, contentStr, `"Gateway"`,
		"must have an S3 gateway endpoint with type Gateway")
	assert.Contains(t, contentStr, ".s3",
		"S3 gateway endpoint must reference the S3 service")

	// Assert: private_dns_enabled = true on interface endpoints
	assert.Contains(t, contentStr, "private_dns_enabled = true",
		"interface endpoints must have private_dns_enabled = true")

	// Assert: Security group restricts to VPC CIDR on port 443
	assert.Contains(t, contentStr, "443",
		"endpoint security group must allow port 443")
	assert.Contains(t, contentStr, "var.vpc_cidr",
		"endpoint security group must restrict to VPC CIDR")
}

// TestProperty16_ExternalVPCNoEndpoints asserts that external VPCs do NOT
// provision VPC endpoints (they use NAT gateways for egress).
//
// Validates: Requirements 15.3
func TestProperty16_ExternalVPCNoEndpoints(t *testing.T) {
	t.Parallel()

	wd, err := os.Getwd()
	require.NoError(t, err)
	endpointsPath := filepath.Join(wd, "..", "modules", "networking", "vpc-endpoints.tf")
	content, err := os.ReadFile(endpointsPath)
	require.NoError(t, err)

	contentStr := string(content)

	// Assert: endpoints are only created for internal (is_internal check)
	// The for_each uses `local.is_internal ? toset(...) : toset([])`
	assert.Contains(t, contentStr, "is_internal",
		"VPC endpoints must be gated on is_internal flag")

	// Count occurrences of is_internal — should appear in interface, s3, and SG
	count := strings.Count(contentStr, "is_internal")
	assert.GreaterOrEqual(t, count, 3,
		"is_internal must gate interface endpoints, S3 endpoint, and security group (found %d)", count)
}

// networkingModulePath is defined in internal_vpc_test.go (shared helper).
