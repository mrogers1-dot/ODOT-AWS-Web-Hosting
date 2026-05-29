// Feature: odot-aws-web-hosting, Property 9: Terraform state keys are unique per account-stage combination
//
// This file verifies that all six (account, stage) pairs have unique Terraform
// state keys in their backend.tf files, each matching the pattern
// {account}-{stage}/terraform.tfstate.
//
// Validates: Requirements 8.5

package test

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclparse"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/zclconf/go-cty/cty"
)

// accountStagePair represents one of the six (account, stage) combinations.
type accountStagePair struct {
	Account string
	Stage   string
}

// allAccountStagePairs returns the six expected (account, stage) combinations.
func allAccountStagePairs() []accountStagePair {
	return []accountStagePair{
		{Account: "internal", Stage: "dev"},
		{Account: "internal", Stage: "test"},
		{Account: "internal", Stage: "prod"},
		{Account: "external", Stage: "dev"},
		{Account: "external", Stage: "test"},
		{Account: "external", Stage: "prod"},
	}
}

// stackDir returns the path to a stack's directory given an account-stage pair.
func stackDir(t *testing.T, pair accountStagePair) string {
	t.Helper()
	wd, err := os.Getwd()
	require.NoError(t, err, "could not determine working directory")
	return filepath.Join(wd, "..", "stacks", fmt.Sprintf("%s-%s", pair.Account, pair.Stage))
}

// extractBackendKey parses a backend.tf file and extracts the "key" attribute
// from the terraform { backend "s3" { ... } } block.
func extractBackendKey(t *testing.T, backendTFPath string) string {
	t.Helper()

	parser := hclparse.NewParser()
	file, diags := parser.ParseHCLFile(backendTFPath)
	require.False(t, diags.HasErrors(), "failed to parse %s: %s", backendTFPath, diags.Error())

	body := file.Body
	content, _, diags := body.PartialContent(&hcl.BodySchema{
		Blocks: []hcl.BlockHeaderSchema{
			{Type: "terraform"},
		},
	})
	require.False(t, diags.HasErrors(), "failed to read terraform block in %s: %s", backendTFPath, diags.Error())
	require.NotEmpty(t, content.Blocks, "no terraform block found in %s", backendTFPath)

	terraformBlock := content.Blocks[0]
	terraformContent, _, diags := terraformBlock.Body.PartialContent(&hcl.BodySchema{
		Blocks: []hcl.BlockHeaderSchema{
			{Type: "backend", LabelNames: []string{"type"}},
		},
	})
	require.False(t, diags.HasErrors(), "failed to read backend block in %s: %s", backendTFPath, diags.Error())
	require.NotEmpty(t, terraformContent.Blocks, "no backend block found in %s", backendTFPath)

	backendBlock := terraformContent.Blocks[0]
	backendContent, diags := backendBlock.Body.Content(&hcl.BodySchema{
		Attributes: []hcl.AttributeSchema{
			{Name: "bucket"},
			{Name: "key", Required: true},
			{Name: "region"},
			{Name: "encrypt"},
			{Name: "dynamodb_table"},
		},
	})
	require.False(t, diags.HasErrors(), "failed to read backend attributes in %s: %s", backendTFPath, diags.Error())

	keyAttr, ok := backendContent.Attributes["key"]
	require.True(t, ok, "key attribute not found in backend block of %s", backendTFPath)

	keyVal, diags := keyAttr.Expr.Value(nil)
	require.False(t, diags.HasErrors(), "failed to evaluate key attribute in %s: %s", backendTFPath, diags.Error())
	require.Equal(t, cty.String, keyVal.Type(), "key attribute must be a string in %s", backendTFPath)

	return keyVal.AsString()
}

// TestStateKeysAreUniquePerAccountStage verifies Property 9:
// All six (account, stage) pairs have distinct state keys, each matching
// the pattern {account}-{stage}/terraform.tfstate.
//
// Validates: Requirements 8.5
func TestStateKeysAreUniquePerAccountStage(t *testing.T) {
	t.Parallel()

	pairs := allAccountStagePairs()
	expectedPattern := regexp.MustCompile(`^[a-z]+-[a-z]+/terraform\.tfstate$`)

	keys := make(map[string]string) // key value → "account-stage" that produced it

	for _, pair := range pairs {
		pairName := fmt.Sprintf("%s-%s", pair.Account, pair.Stage)
		backendPath := filepath.Join(stackDir(t, pair), "backend.tf")

		// Verify the backend.tf file exists.
		_, err := os.Stat(backendPath)
		require.NoError(t, err, "backend.tf must exist for stack %s", pairName)

		// Extract the key value from the HCL.
		key := extractBackendKey(t, backendPath)

		// Assert the key matches the expected pattern.
		assert.True(t, expectedPattern.MatchString(key),
			"state key for %s must match pattern {account}-{stage}/terraform.tfstate; got %q",
			pairName, key)

		// Assert the key matches the specific expected value for this pair.
		expectedKey := fmt.Sprintf("%s-%s/terraform.tfstate", pair.Account, pair.Stage)
		assert.Equal(t, expectedKey, key,
			"state key for stack %s must be %q; got %q", pairName, expectedKey, key)

		// Assert uniqueness: no other pair should have produced this key.
		if existingPair, exists := keys[key]; exists {
			t.Errorf("state key %q is duplicated: used by both %s and %s",
				key, existingPair, pairName)
		}
		keys[key] = pairName
	}

	// Final assertion: we must have exactly 6 distinct keys.
	assert.Equal(t, 6, len(keys),
		"expected 6 unique state keys, got %d", len(keys))
}
