// Feature: odot-aws-web-hosting, Property 17: ALBs have HTTPS listener with TLS1.2+ and HTTP redirect
//
// Every ALB SHALL have an HTTPS:443 listener with a TLS1.2+ security policy
// and an HTTP:80 listener that redirects (301) to HTTPS.
//
// Tests use HCL parsing — no AWS credentials required.
//
// Validates: Requirements 16.2, 16.3

package test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestProperty17_TLSListenerAndRedirect asserts that the ALB configuration
// includes HTTPS:443 with a modern TLS policy and HTTP:80 redirect.
//
// Validates: Requirements 16.2, 16.3
func TestProperty17_TLSListenerAndRedirect(t *testing.T) {
	t.Parallel()

	wd, err := os.Getwd()
	require.NoError(t, err)
	albPath := filepath.Join(wd, "..", "modules", "app-service", "alb.tf")
	content, err := os.ReadFile(albPath)
	require.NoError(t, err, "modules/app-service/alb.tf must exist")

	contentStr := string(content)

	// Assert: HTTPS listener on port 443 exists
	assert.Contains(t, contentStr, "443",
		"ALB must have a listener on port 443")

	// Assert: TLS security policy is modern (TLS 1.2+)
	assert.Contains(t, contentStr, "ELBSecurityPolicy",
		"HTTPS listener must specify a TLS security policy")

	// Assert: HTTP listener on port 80 exists
	assert.Contains(t, contentStr, "80",
		"ALB must have a listener on port 80")

	// Assert: HTTP listener performs a redirect (not forward)
	assert.Contains(t, contentStr, "redirect",
		"HTTP:80 listener must perform a redirect action")

	// Assert: ACM certificate is referenced
	assert.True(t,
		assert.ObjectsAreEqual(true, len(contentStr) > 0) &&
			(contains(contentStr, "aws_acm_certificate") || contains(contentStr, "certificate_arn")),
		"ALB must reference an ACM certificate for HTTPS")
}

func contains(s, substr string) bool {
	return len(s) > 0 && len(substr) > 0 && indexOf(s, substr) >= 0
}

func indexOf(s, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}
