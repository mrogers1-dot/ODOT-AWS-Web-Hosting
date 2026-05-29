// helpers_test.go provides shared utility functions for all test files in this package.

package test

import (
	tfjson "github.com/hashicorp/terraform-json"
)

// isNoOpAction returns true if the action set represents a no-op (no changes).
func isNoOpAction(actions tfjson.Actions) bool {
	if len(actions) == 0 {
		return true
	}
	if len(actions) == 1 && actions[0] == "no-op" {
		return true
	}
	return false
}

// isReadAction returns true if the action set represents a read (data source).
func isReadAction(actions tfjson.Actions) bool {
	if len(actions) == 1 && actions[0] == "read" {
		return true
	}
	return false
}
