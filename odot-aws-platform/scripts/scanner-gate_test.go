// Feature: odot-aws-web-hosting, Scanner gate unit tests
//
// This file contains unit tests for the EvaluateScanResult function.
// Tests verify correct behavior for both Trivy JSON and Inspector CycloneDX
// SBOM formats, including edge cases and error handling.
//
// Requirements: 6.3, 6.4
package main

import (
	"testing"
)

// ── Trivy Format Tests ───────────────────────────────────────────────────────

func TestTrivyFormat_CriticalSeverity_ReturnsFail(t *testing.T) {
	doc := ScanDocument{
		Results: []TrivyResult{
			{
				Target: "myimage:latest",
				Vulnerabilities: []TrivyVulnerability{
					{VulnerabilityID: "CVE-2024-0001", Severity: "CRITICAL"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GateFail {
		t.Errorf("expected FAIL for CRITICAL severity, got %s", result)
	}
}

func TestTrivyFormat_HighSeverity_ReturnsFail(t *testing.T) {
	doc := ScanDocument{
		Results: []TrivyResult{
			{
				Target: "myimage:latest",
				Vulnerabilities: []TrivyVulnerability{
					{VulnerabilityID: "CVE-2024-0002", Severity: "HIGH"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GateFail {
		t.Errorf("expected FAIL for HIGH severity, got %s", result)
	}
}

func TestTrivyFormat_MediumSeverity_ReturnsPass(t *testing.T) {
	doc := ScanDocument{
		Results: []TrivyResult{
			{
				Target: "myimage:latest",
				Vulnerabilities: []TrivyVulnerability{
					{VulnerabilityID: "CVE-2024-0003", Severity: "MEDIUM"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GatePass {
		t.Errorf("expected PASS for MEDIUM severity, got %s", result)
	}
}

func TestTrivyFormat_LowSeverity_ReturnsPass(t *testing.T) {
	doc := ScanDocument{
		Results: []TrivyResult{
			{
				Target: "myimage:latest",
				Vulnerabilities: []TrivyVulnerability{
					{VulnerabilityID: "CVE-2024-0004", Severity: "LOW"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GatePass {
		t.Errorf("expected PASS for LOW severity, got %s", result)
	}
}

func TestTrivyFormat_MixedSeverities_HighPresent_ReturnsFail(t *testing.T) {
	doc := ScanDocument{
		Results: []TrivyResult{
			{
				Target: "myimage:latest",
				Vulnerabilities: []TrivyVulnerability{
					{VulnerabilityID: "CVE-2024-0005", Severity: "LOW"},
					{VulnerabilityID: "CVE-2024-0006", Severity: "MEDIUM"},
					{VulnerabilityID: "CVE-2024-0007", Severity: "HIGH"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GateFail {
		t.Errorf("expected FAIL when HIGH is present among mixed severities, got %s", result)
	}
}

func TestTrivyFormat_MultipleResults_CriticalInSecond_ReturnsFail(t *testing.T) {
	doc := ScanDocument{
		Results: []TrivyResult{
			{
				Target: "layer1",
				Vulnerabilities: []TrivyVulnerability{
					{VulnerabilityID: "CVE-2024-0008", Severity: "LOW"},
				},
			},
			{
				Target: "layer2",
				Vulnerabilities: []TrivyVulnerability{
					{VulnerabilityID: "CVE-2024-0009", Severity: "CRITICAL"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GateFail {
		t.Errorf("expected FAIL when CRITICAL is in second result, got %s", result)
	}
}

func TestTrivyFormat_NoVulnerabilities_ReturnsPass(t *testing.T) {
	doc := ScanDocument{
		Results: []TrivyResult{
			{
				Target:          "myimage:latest",
				Vulnerabilities: []TrivyVulnerability{},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GatePass {
		t.Errorf("expected PASS for empty vulnerabilities list, got %s", result)
	}
}

func TestTrivyFormat_CaseInsensitive_ReturnsFail(t *testing.T) {
	doc := ScanDocument{
		Results: []TrivyResult{
			{
				Target: "myimage:latest",
				Vulnerabilities: []TrivyVulnerability{
					{VulnerabilityID: "CVE-2024-0010", Severity: "Critical"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GateFail {
		t.Errorf("expected FAIL for mixed-case 'Critical', got %s", result)
	}
}

// ── CycloneDX (Inspector SBOM) Format Tests ──────────────────────────────────

func TestCycloneDX_CriticalRating_ReturnsFail(t *testing.T) {
	doc := ScanDocument{
		Vulnerabilities: []CycloneDXVulnerability{
			{
				ID: "CVE-2024-1001",
				Ratings: []CycloneDXRating{
					{Severity: "critical"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GateFail {
		t.Errorf("expected FAIL for critical rating in CycloneDX, got %s", result)
	}
}

func TestCycloneDX_HighRating_ReturnsFail(t *testing.T) {
	doc := ScanDocument{
		Vulnerabilities: []CycloneDXVulnerability{
			{
				ID: "CVE-2024-1002",
				Ratings: []CycloneDXRating{
					{Severity: "high"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GateFail {
		t.Errorf("expected FAIL for high rating in CycloneDX, got %s", result)
	}
}

func TestCycloneDX_MediumRating_ReturnsPass(t *testing.T) {
	doc := ScanDocument{
		Vulnerabilities: []CycloneDXVulnerability{
			{
				ID: "CVE-2024-1003",
				Ratings: []CycloneDXRating{
					{Severity: "medium"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GatePass {
		t.Errorf("expected PASS for medium rating in CycloneDX, got %s", result)
	}
}

func TestCycloneDX_LowRating_ReturnsPass(t *testing.T) {
	doc := ScanDocument{
		Vulnerabilities: []CycloneDXVulnerability{
			{
				ID: "CVE-2024-1004",
				Ratings: []CycloneDXRating{
					{Severity: "low"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GatePass {
		t.Errorf("expected PASS for low rating in CycloneDX, got %s", result)
	}
}

func TestCycloneDX_MultipleRatings_HighPresent_ReturnsFail(t *testing.T) {
	doc := ScanDocument{
		Vulnerabilities: []CycloneDXVulnerability{
			{
				ID: "CVE-2024-1005",
				Ratings: []CycloneDXRating{
					{Severity: "medium"},
					{Severity: "high"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GateFail {
		t.Errorf("expected FAIL when high rating is present among multiple ratings, got %s", result)
	}
}

func TestCycloneDX_MultipleVulnerabilities_CriticalInSecond_ReturnsFail(t *testing.T) {
	doc := ScanDocument{
		Vulnerabilities: []CycloneDXVulnerability{
			{
				ID:      "CVE-2024-1006",
				Ratings: []CycloneDXRating{{Severity: "low"}},
			},
			{
				ID:      "CVE-2024-1007",
				Ratings: []CycloneDXRating{{Severity: "critical"}},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GateFail {
		t.Errorf("expected FAIL when critical is in second vulnerability, got %s", result)
	}
}

func TestCycloneDX_NoVulnerabilities_ReturnsPass(t *testing.T) {
	doc := ScanDocument{
		Vulnerabilities: []CycloneDXVulnerability{},
	}
	result := EvaluateScanResult(doc)
	if result != GatePass {
		t.Errorf("expected PASS for empty vulnerabilities list, got %s", result)
	}
}

func TestCycloneDX_EmptyRatings_ReturnsPass(t *testing.T) {
	doc := ScanDocument{
		Vulnerabilities: []CycloneDXVulnerability{
			{
				ID:      "CVE-2024-1008",
				Ratings: []CycloneDXRating{},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GatePass {
		t.Errorf("expected PASS for vulnerability with empty ratings, got %s", result)
	}
}

// ── Edge Cases ───────────────────────────────────────────────────────────────

func TestEmptyDocument_ReturnsPass(t *testing.T) {
	doc := ScanDocument{}
	result := EvaluateScanResult(doc)
	if result != GatePass {
		t.Errorf("expected PASS for empty document, got %s", result)
	}
}

func TestInformationalSeverity_ReturnsPass(t *testing.T) {
	doc := ScanDocument{
		Results: []TrivyResult{
			{
				Target: "myimage:latest",
				Vulnerabilities: []TrivyVulnerability{
					{VulnerabilityID: "CVE-2024-0011", Severity: "INFORMATIONAL"},
				},
			},
		},
	}
	result := EvaluateScanResult(doc)
	if result != GatePass {
		t.Errorf("expected PASS for INFORMATIONAL severity, got %s", result)
	}
}

// ── ParseAndEvaluate Tests ───────────────────────────────────────────────────

func TestParseAndEvaluate_ValidTrivyJSON_ReturnsFail(t *testing.T) {
	input := []byte(`{
		"Results": [{
			"Target": "myimage:latest",
			"Vulnerabilities": [{
				"VulnerabilityID": "CVE-2024-0001",
				"Severity": "CRITICAL"
			}]
		}]
	}`)
	result, err := ParseAndEvaluate(input)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != GateFail {
		t.Errorf("expected FAIL, got %s", result)
	}
}

func TestParseAndEvaluate_ValidCycloneDXJSON_ReturnsFail(t *testing.T) {
	input := []byte(`{
		"vulnerabilities": [{
			"id": "CVE-2024-1001",
			"ratings": [{"severity": "high"}]
		}]
	}`)
	result, err := ParseAndEvaluate(input)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != GateFail {
		t.Errorf("expected FAIL, got %s", result)
	}
}

func TestParseAndEvaluate_ValidJSON_NoHighFindings_ReturnsPass(t *testing.T) {
	input := []byte(`{
		"Results": [{
			"Target": "myimage:latest",
			"Vulnerabilities": [{
				"VulnerabilityID": "CVE-2024-0003",
				"Severity": "MEDIUM"
			}]
		}]
	}`)
	result, err := ParseAndEvaluate(input)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != GatePass {
		t.Errorf("expected PASS, got %s", result)
	}
}

func TestParseAndEvaluate_MalformedJSON_ReturnsError(t *testing.T) {
	input := []byte(`{not valid json`)
	_, err := ParseAndEvaluate(input)
	if err == nil {
		t.Error("expected error for malformed JSON, got nil")
	}
}

func TestParseAndEvaluate_EmptyInput_ReturnsError(t *testing.T) {
	_, err := ParseAndEvaluate([]byte{})
	if err == nil {
		t.Error("expected error for empty input, got nil")
	}
}

func TestParseAndEvaluate_EmptyObject_ReturnsPass(t *testing.T) {
	input := []byte(`{}`)
	result, err := ParseAndEvaluate(input)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != GatePass {
		t.Errorf("expected PASS for empty JSON object, got %s", result)
	}
}
