package mlsstate

import "strings"

func (proposal Proposal) Validate() error {
	if strings.TrimSpace(proposal.ID) == "" || strings.TrimSpace(proposal.ConversationID) == "" ||
		strings.TrimSpace(proposal.AuthorAccountID) == "" || strings.TrimSpace(proposal.AuthorDeviceID) == "" ||
		proposal.BaseEpoch < 0 || len(proposal.Data) == 0 || len(proposal.Data) > maxMaterialBytes || proposal.CreatedAt.IsZero() {
		return ErrInvalidProposal
	}
	return nil
}
