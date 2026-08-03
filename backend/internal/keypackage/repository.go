package keypackage

import (
	"context"
	"time"
)

// Repository coordinates public MLS KeyPackages. Claim must be atomic and
// consume each returned package exactly once.
type Repository interface {
	Publish(ctx context.Context, accountID, deviceID string, items []Publish) error
	ListAvailable(ctx context.Context, accountID string, limit int, now time.Time) ([]KeyPackage, error)
	Claim(ctx context.Context, accountID string, limit int, now time.Time) ([]KeyPackage, error)
}
