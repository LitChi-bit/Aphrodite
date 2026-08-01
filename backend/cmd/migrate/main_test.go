package main

import (
	"context"
	"testing"
)

func TestRunRejectsBaselineWithoutExplicitConfirmation(t *testing.T) {
	t.Setenv("APHRODITE_DATABASE_URL", "postgres://example.invalid/test")
	err := run(context.Background(), []string{"-baseline"})
	if err == nil || err.Error() != "baseline requires -confirm "+baselineConfirmation {
		t.Fatalf("baseline confirmation error = %v", err)
	}
}

func TestRunRejectsMissingDatabaseURL(t *testing.T) {
	t.Setenv("APHRODITE_DATABASE_URL", "")
	err := run(context.Background(), nil)
	if err == nil || err.Error() != "APHRODITE_DATABASE_URL is required" {
		t.Fatalf("database URL error = %v", err)
	}
}
