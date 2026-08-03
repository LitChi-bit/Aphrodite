package keypackage

import (
	"testing"
	"time"
)

func TestValidatePublishRejectsInvalidOrDuplicateEntries(t *testing.T) {
	now := time.Date(2026, 7, 31, 0, 0, 0, 0, time.UTC)
	valid := Publish{ID: "key-package-example", Ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519", Package: []byte{1}, Signature: []byte{2}, CreatedAt: now, ExpiresAt: now.Add(time.Hour)}
	if err := ValidatePublish([]Publish{valid}); err != nil {
		t.Fatalf("valid publish = %v", err)
	}
	if err := ValidatePublish([]Publish{valid, valid}); err != ErrInvalidKeyPackage {
		t.Fatalf("duplicate publish = %v", err)
	}
	valid.Package = nil
	if err := ValidatePublish([]Publish{valid}); err != ErrInvalidKeyPackage {
		t.Fatalf("empty package = %v", err)
	}
}

func TestValidateLimit(t *testing.T) {
	for _, limit := range []int{1, 20} {
		if err := ValidateLimit(limit); err != nil {
			t.Fatalf("limit %d = %v", limit, err)
		}
	}
	for _, limit := range []int{0, 21} {
		if err := ValidateLimit(limit); err != ErrInvalidLimit {
			t.Fatalf("limit %d = %v", limit, err)
		}
	}
}
