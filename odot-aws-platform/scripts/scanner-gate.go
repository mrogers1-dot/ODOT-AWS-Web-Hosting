// Package main implements the scanner gate logic for the ODOT CI/CD pipeline.
//
// The EvaluateScanResult function parses vulnerability scan output from either
// Trivy (JSON format) or Amazon Inspector (CycloneDX SBOM format) and returns
// FAIL if any finding has severity CRITICAL or HIGH, otherwise PASS.
//
// Requirements: 6.3, 6.4
package main

import (
	"encoding/json"
	"fmt"
	"strings"
)

// GateResult represents the outcome of a scanner gate evaluation.
type GateResult string

const (
	// GatePass indicates no Critical or High severity findings were detected.
	GatePass GateResult = "PASS"
	// GateFail indicates at least one Critical or High severity finding was detected.
	GateFail GateResult = "FAIL"
)

// ScanDocument is a unified structure that can unmarshal either Trivy JSON
// output or Inspector CycloneDX SBOM output. The format is auto-detected
// based on which fields are populated after unmarshaling.
type ScanDocument struct {
	// Trivy JSON format fields
	Results []TrivyResult `json:"Results"`

	// CycloneDX (Inspector SBOM) format fields
	Vulnerabilities []CycloneDXVulnerability `json:"vulnerabilities"`
}

// TrivyResult represents a single result entry in Trivy JSON output.
type TrivyResult struct {
	Target          string              `json:"Target"`
	Vulnerabilities []TrivyVulnerability `json:"Vulnerabilities"`
}

// TrivyVulnerability represents a single vulnerability finding in Trivy output.
type TrivyVulnerability struct {
	VulnerabilityID string `json:"VulnerabilityID"`
	Severity        string `json:"Severity"`
	Title           string `json:"Title"`
	Description     string `json:"Description"`
}

// CycloneDXVulnerability represents a vulnerability entry in CycloneDX SBOM format
// as produced by Amazon Inspector.
type CycloneDXVulnerability struct {
	ID      string             `json:"id"`
	Ratings []CycloneDXRating  `json:"ratings"`
}

// CycloneDXRating represents a severity rating within a CycloneDX vulnerability.
type CycloneDXRating struct {
	Severity string `json:"severity"`
}

// EvaluateScanResult evaluates a scan document and returns GateFail if any
// finding has severity CRITICAL or HIGH. It handles both Trivy JSON format
// and Inspector CycloneDX SBOM format. Returns GatePass if no high-severity
// findings are present.
//
// The function auto-detects the format:
//   - If Results[] is populated → Trivy format (checks Results[].Vulnerabilities[].Severity)
//   - If vulnerabilities[] is populated → CycloneDX format (checks vulnerabilities[].ratings[].severity)
//   - If both are empty → PASS (no findings)
func EvaluateScanResult(doc ScanDocument) GateResult {
	// Check Trivy format: Results[].Vulnerabilities[].Severity
	for _, result := range doc.Results {
		for _, vuln := range result.Vulnerabilities {
			if isHighSeverity(vuln.Severity) {
				return GateFail
			}
		}
	}

	// Check CycloneDX (Inspector SBOM) format: vulnerabilities[].ratings[].severity
	for _, vuln := range doc.Vulnerabilities {
		for _, rating := range vuln.Ratings {
			if isHighSeverity(rating.Severity) {
				return GateFail
			}
		}
	}

	return GatePass
}

// ParseAndEvaluate parses raw JSON bytes into a ScanDocument and evaluates it.
// Returns an error if the JSON is malformed.
func ParseAndEvaluate(data []byte) (GateResult, error) {
	if len(data) == 0 {
		return "", fmt.Errorf("scanner gate: empty input document")
	}

	var doc ScanDocument
	if err := json.Unmarshal(data, &doc); err != nil {
		return "", fmt.Errorf("scanner gate: failed to parse scan document: %w", err)
	}

	return EvaluateScanResult(doc), nil
}

// isHighSeverity returns true if the severity string (case-insensitive)
// matches CRITICAL or HIGH.
func isHighSeverity(severity string) bool {
	upper := strings.ToUpper(strings.TrimSpace(severity))
	return upper == "CRITICAL" || upper == "HIGH"
}

func main() {
	// This file is primarily a library consumed by tests and the CI/CD pipeline.
	// When run directly, it reads stdin and outputs the gate result.
	fmt.Println("scanner-gate: use ParseAndEvaluate() or EvaluateScanResult() programmatically")
}
