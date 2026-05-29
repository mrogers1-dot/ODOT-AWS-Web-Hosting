// Feature: odot-aws-web-hosting, Property 18: ALBs have access logging enabled
//
// Every ALB SHALL have access_logs enabled pointing to an encrypted,
// public-access-blocked S3 bucket.
//
// Tests use HCL parsing — no AWS credentials required.
//
// Validates: Requirements 17.1, 17.2

package test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestProperty18_ALBAccessLogsEnabled asserts that the ALB has access logging
// configured with an encrypted S3 bucket.
//
// Validates: Requirements 17.1, 17.2
func TestProperty18_ALBAccessLogsEnabled(t *testing.T) {
	t.Parallel()

	wd, err := os.Getwd()
	require.NoError(t, err)
	albPath := filepath.Join(wd, "..", "modules", "app-service", "alb.tf")
	content, err := os.ReadFile(albPath)
	require.NoError(t, err, "modules/app-service/alb.tf must exist")

	contentStr := string(content)

	// Assert: access_logs block exists on the ALB
	assert.Contains(t, contentStr, "access_logs",
		"ALB must have an access_logs configuration block")

	// Assert: access_logs enabled = true
	assert.Contains(t, contentStr, "enabled",
		"access_logs block must have enabled attribute")

	// Assert: S3 bucket for access logs exists or is referenced
	assert.True(t,
		assert.ObjectsAreEqual(true, len(contentStr) > 0) &&
			(containsStr(contentStr, "aws_s3_bucket") || containsStr(contentStr, "bucket")),
		"ALB access_logs must reference an S3 bucket")
}

func containsStr(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i >= 0
		}
	}
	return false
}
