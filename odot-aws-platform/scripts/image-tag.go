// Package main provides CI/CD utility functions for the ODOT AWS Web Hosting platform.
package main

// GenerateTags produces the set of Docker image tags for a given build.
// It returns a slice containing the exact commit SHA (immutable tag) and
// a branch-based "latest" tag (mutable, always points to the most recent
// build for that branch).
//
// Requirements: 6.5
func GenerateTags(commitSHA, branchName string) []string {
	return []string{
		commitSHA,
		branchName + "-latest",
	}
}
