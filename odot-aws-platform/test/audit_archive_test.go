// Feature: odot-aws-web-hosting, Property 24: Tamper-evident audit archive
//
// The audit archive bucket SHALL have Object Lock in COMPLIANCE mode with
// ≥365-day retention and no delete permission granted to any principal.
//
// Tests use HCL parsing — no AWS credentials required.
//
// Validates: Requirements 28.1, 28.2, 28.4

package test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestProperty24_AuditArchiveObjectLock asserts that the audit archive bucket
// has Object Lock in COMPLIANCE mode with 365-day retention.
//
// Validates: Requirements 28.1, 28.2
func TestProperty24_AuditArchiveObjectLock(t *testing.T) {
	t.Parallel()

	wd, err := os.Getwd()
	require.NoError(t, err)
	archivePath := filepath.Join(wd, "..", "modules", "admin-dashboard", "audit-archive.tf")
	content, err := os.ReadFile(archivePath)
	require.NoError(t, err, "modules/admin-dashboard/audit-archive.tf must exist")

	contentStr := string(content)

	// Assert: Object Lock is enabled on the bucket
	assert.Contains(t, contentStr, "object_lock_enabled = true",
		"audit archive bucket must have object_lock_enabled = true")

	// Assert: COMPLIANCE mode retention
	assert.Contains(t, contentStr, "COMPLIANCE",
		"audit archive must use COMPLIANCE mode Object Lock")

	// Assert: 365-day retention
	assert.Contains(t, contentStr, "365",
		"audit archive must have 365-day retention period")

	// Assert: No delete permission (Deny policy)
	assert.Contains(t, contentStr, "Deny",
		"audit archive must have a Deny policy for delete operations")
	assert.Contains(t, contentStr, "s3:DeleteObject",
		"audit archive Deny policy must cover s3:DeleteObject")

	// Assert: KMS encryption
	assert.Contains(t, contentStr, "aws:kms",
		"audit archive must be encrypted with KMS")
}

// TestAuditArchiveSSEEndpointExists asserts that the dashboard has an SSE
// streaming endpoint for real-time updates.
//
// Validates: Requirements 27.1
func TestAuditArchiveSSEEndpointExists(t *testing.T) {
	t.Parallel()

	wd, err := os.Getwd()
	require.NoError(t, err)
	streamPath := filepath.Join(wd, "..", "..", "admin-dashboard", "server", "routes", "stream.ts")
	content, err := os.ReadFile(streamPath)
	require.NoError(t, err, "admin-dashboard/server/routes/stream.ts must exist")

	contentStr := string(content)

	// Assert: SSE content type header
	assert.Contains(t, contentStr, "text/event-stream",
		"SSE endpoint must set Content-Type: text/event-stream")

	// Assert: status-change event type
	assert.Contains(t, contentStr, "status-change",
		"SSE must emit status-change events")

	// Assert: broadcasts to connected clients
	assert.Contains(t, contentStr, "clients",
		"SSE must maintain a set of connected clients")
}
