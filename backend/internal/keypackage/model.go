package keypackage

import (
	"errors"
	"strings"
	"time"
)

const (
	maxBatchSize      = 20
	maxKeyPackageSize = 64 << 10
	maxSignatureSize  = 16 << 10
)

var (
	ErrInvalidKeyPackage = errors.New("invalid key package")
	ErrInvalidLimit      = errors.New("invalid limit")
)

// KeyPackage contains only MLS public coordination material. It must never
// contain an MLS private key, group secret, or decrypted application message.
type KeyPackage struct {
	ID                  string
	AccountID           string
	DeviceID            string
	Ciphersuite         string
	Package             []byte
	Signature           []byte
	CreatedAt           time.Time
	ExpiresAt           time.Time
	ConsumedAt          *time.Time
	ConsumedByAccountID *string
	ConsumedByDeviceID  *string
	ConsumedBySessionID *string
}

type Publish struct {
	ID          string
	Ciphersuite string
	Package     []byte
	Signature   []byte
	ExpiresAt   time.Time
	CreatedAt   time.Time
}

func (item Publish) Validate() error {
	if strings.TrimSpace(item.ID) == "" || strings.TrimSpace(item.Ciphersuite) == "" ||
		len(item.Ciphersuite) > 128 || len(item.Package) == 0 || len(item.Package) > maxKeyPackageSize ||
		len(item.Signature) == 0 || len(item.Signature) > maxSignatureSize || item.CreatedAt.IsZero() ||
		!item.ExpiresAt.After(item.CreatedAt) {
		return ErrInvalidKeyPackage
	}
	return nil
}

func ValidatePublish(items []Publish) error {
	if len(items) == 0 || len(items) > maxBatchSize {
		return ErrInvalidKeyPackage
	}
	seen := make(map[string]struct{}, len(items))
	for _, item := range items {
		if err := item.Validate(); err != nil {
			return err
		}
		if _, exists := seen[item.ID]; exists {
			return ErrInvalidKeyPackage
		}
		seen[item.ID] = struct{}{}
	}
	return nil
}

func ValidateLimit(limit int) error {
	if limit < 1 || limit > maxBatchSize {
		return ErrInvalidLimit
	}
	return nil
}
