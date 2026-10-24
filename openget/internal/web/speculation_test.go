package web

import (
	"encoding/json"
	"testing"
)

// A rule set that fails to parse is dropped silently by the browser, so a stray comma would quietly turn the feature off. Catch it here instead.
func TestSpeculationRulesIsJSON(t *testing.T) {
	var v map[string]any
	if err := json.Unmarshal([]byte(speculationRulesJSON), &v); err != nil {
		t.Fatalf("speculation rules are not valid JSON: %v", err)
	}
	if _, ok := v["prerender"]; !ok {
		t.Fatal("speculation rules have no prerender list")
	}
}
