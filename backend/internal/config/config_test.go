package config

import (
	"testing"
	"time"
)

func TestLoadUsesSafeDefaults(t *testing.T) {
	clearConfigEnvironment(t)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Address() != "127.0.0.1:8080" {
		t.Fatalf("Address() = %q", cfg.Address())
	}
	if cfg.ReadTimeout != 10*time.Second {
		t.Fatalf("ReadTimeout = %v", cfg.ReadTimeout)
	}
}

func TestLoadRejectsInvalidPort(t *testing.T) {
	clearConfigEnvironment(t)
	t.Setenv("APHRODITE_HTTP_PORT", "70000")

	if _, err := Load(); err == nil {
		t.Fatal("Load() expected invalid port error")
	}
}

func TestLoadReadsOverrides(t *testing.T) {
	clearConfigEnvironment(t)
	t.Setenv("APHRODITE_HTTP_HOST", "0.0.0.0")
	t.Setenv("APHRODITE_HTTP_PORT", "9090")
	t.Setenv("APHRODITE_SHUTDOWN_TIMEOUT", "20s")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Address() != "0.0.0.0:9090" {
		t.Fatalf("Address() = %q", cfg.Address())
	}
	if cfg.ShutdownTimeout != 20*time.Second {
		t.Fatalf("ShutdownTimeout = %v", cfg.ShutdownTimeout)
	}
}

func clearConfigEnvironment(t *testing.T) {
	t.Helper()
	for _, key := range []string{
		"APHRODITE_ENV",
		"APHRODITE_HTTP_HOST",
		"APHRODITE_HTTP_PORT",
		"APHRODITE_READ_TIMEOUT",
		"APHRODITE_WRITE_TIMEOUT",
		"APHRODITE_IDLE_TIMEOUT",
		"APHRODITE_SHUTDOWN_TIMEOUT",
	} {
		t.Setenv(key, "")
	}
}
