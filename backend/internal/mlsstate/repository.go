package mlsstate

import "context"

type Repository interface {
	Commit(ctx context.Context, accountID string, commit Commit) (GroupState, error)
	GetState(ctx context.Context, accountID, conversationID string) (GroupState, error)
	ClaimWelcome(ctx context.Context, accountID, deviceID string) ([]Delivery, error)
}
