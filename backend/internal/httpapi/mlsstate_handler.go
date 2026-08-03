package httpapi

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/mlsstate"
)

const maxMLSStateRequestBodyBytes = 3 << 20

type MLSStateService interface {
	Commit(context.Context, string, string, mlsstate.Commit) (mlsstate.GroupState, error)
	GetState(context.Context, string, string, string) (mlsstate.GroupState, error)
	ClaimWelcome(context.Context, string, string) ([]mlsstate.Delivery, error)
	ListDeviceRoster(context.Context, string, string) ([]mlsstate.DeviceRosterEntry, error)
	PublishProposal(context.Context, mlsstate.Proposal) (mlsstate.Proposal, error)
	ListProposals(context.Context, string, string, string) ([]mlsstate.Proposal, error)
}

type mlsStateHandler struct {
	service       MLSStateService
	authenticator AccessTokenAuthenticator
	verifier      auth.AccessTokenVerifier
	now           func() time.Time
	newID         func() (string, error)
}

type commitMLSStateRequest struct {
	Epoch          int64            `json:"epoch"`
	GroupInfo      string           `json:"group_info"`
	CommitData     string           `json:"commit"`
	Welcomes       []welcomeRequest `json:"welcomes"`
	RemovedDevices []string         `json:"removed_device_ids"`
	ProposalIDs    []string         `json:"proposal_ids"`
}
type proposalRequest struct {
	BaseEpoch int64  `json:"base_epoch"`
	Proposal  string `json:"proposal"`
}
type welcomeRequest struct {
	TargetAccountID string `json:"target_account_id"`
	TargetDeviceID  string `json:"target_device_id"`
	Welcome         string `json:"welcome"`
}
type groupStateResponse struct {
	ConversationID string    `json:"conversation_id"`
	Epoch          int64     `json:"epoch"`
	GroupInfo      string    `json:"group_info"`
	CommitData     string    `json:"commit"`
	CommittedAt    time.Time `json:"committed_at"`
}
type welcomeResponse struct {
	ID             string    `json:"id"`
	ConversationID string    `json:"conversation_id"`
	Epoch          int64     `json:"epoch"`
	Welcome        string    `json:"welcome"`
	CreatedAt      time.Time `json:"created_at"`
}
type proposalResponse struct {
	ID              string    `json:"id"`
	ConversationID  string    `json:"conversation_id"`
	AuthorAccountID string    `json:"author_account_id"`
	AuthorDeviceID  string    `json:"author_device_id"`
	BaseEpoch       int64     `json:"base_epoch"`
	Proposal        string    `json:"proposal"`
	CreatedAt       time.Time `json:"created_at"`
}

func (h mlsStateHandler) register(mux *http.ServeMux) {
	mux.HandleFunc("PUT /v1/conversations/{conversation_id}/mls/state", requireAccessToken(h.authenticator, h.verifier, h.commit))
	mux.HandleFunc("GET /v1/conversations/{conversation_id}/mls/state", requireAccessToken(h.authenticator, h.verifier, h.get))
	mux.HandleFunc("POST /v1/mls/welcomes:claim", requireAccessToken(h.authenticator, h.verifier, h.claim))
	mux.HandleFunc("GET /v1/conversations/{conversation_id}/mls/devices", requireAccessToken(h.authenticator, h.verifier, h.listRoster))
	mux.HandleFunc("POST /v1/conversations/{conversation_id}/mls/proposals", requireAccessToken(h.authenticator, h.verifier, h.publishProposal))
	mux.HandleFunc("GET /v1/conversations/{conversation_id}/mls/proposals", requireAccessToken(h.authenticator, h.verifier, h.listProposals))
	mux.HandleFunc("/v1/conversations/{conversation_id}/mls/state", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Allow", "GET, PUT")
		writeError(w, r, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	})
	mux.HandleFunc("/v1/mls/welcomes:claim", methodNotAllowed(http.MethodPost))
}

func (h mlsStateHandler) commit(w http.ResponseWriter, r *http.Request) {
	subject, ok := h.subject(w, r)
	if !ok {
		return
	}
	conversationID := strings.TrimSpace(r.PathValue("conversation_id"))
	if conversationID == "" {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "conversation_id is required")
		return
	}
	var request commitMLSStateRequest
	if !decodeMLSStateRequest(w, r, &request) {
		return
	}
	groupInfo, err := base64.RawStdEncoding.DecodeString(request.GroupInfo)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "group_info must be base64")
		return
	}
	commitData, err := base64.RawStdEncoding.DecodeString(request.CommitData)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "commit must be base64")
		return
	}
	welcomes := make([]mlsstate.Welcome, 0, len(request.Welcomes))
	for _, input := range request.Welcomes {
		data, err := base64.RawStdEncoding.DecodeString(input.Welcome)
		if err != nil {
			writeError(w, r, http.StatusBadRequest, "invalid_request", "welcome must be base64")
			return
		}
		id, err := h.newID()
		if err != nil {
			writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
			return
		}
		welcomes = append(welcomes, mlsstate.Welcome{ID: id, TargetAccountID: input.TargetAccountID, TargetDeviceID: input.TargetDeviceID, Data: data})
	}
	state, err := h.service.Commit(r.Context(), subject.AccountID, subject.DeviceID, mlsstate.Commit{ConversationID: conversationID, CommittedDeviceID: subject.DeviceID, Epoch: request.Epoch, GroupInfo: groupInfo, CommitData: commitData, CommittedAt: h.now().UTC(), Welcomes: welcomes, RemovedDevices: request.RemovedDevices, ProposalIDs: request.ProposalIDs})
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	writeData(w, r, http.StatusCreated, toGroupStateResponse(state))
}

func (h mlsStateHandler) get(w http.ResponseWriter, r *http.Request) {
	subject, ok := h.subject(w, r)
	if !ok {
		return
	}
	state, err := h.service.GetState(r.Context(), subject.AccountID, subject.DeviceID, strings.TrimSpace(r.PathValue("conversation_id")))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, toGroupStateResponse(state))
}
func (h mlsStateHandler) publishProposal(w http.ResponseWriter, r *http.Request) {
	subject, ok := h.subject(w, r)
	if !ok {
		return
	}
	var request proposalRequest
	if !decodeMLSStateRequest(w, r, &request) {
		return
	}
	data, err := base64.RawStdEncoding.DecodeString(request.Proposal)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "proposal must be base64")
		return
	}
	id, err := h.newID()
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
		return
	}
	proposal, err := h.service.PublishProposal(r.Context(), mlsstate.Proposal{ID: id, ConversationID: strings.TrimSpace(r.PathValue("conversation_id")), AuthorAccountID: subject.AccountID, AuthorDeviceID: subject.DeviceID, BaseEpoch: request.BaseEpoch, Data: data, CreatedAt: h.now().UTC()})
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	writeData(w, r, http.StatusCreated, toProposalResponse(proposal))
}

func (h mlsStateHandler) listProposals(w http.ResponseWriter, r *http.Request) {
	subject, ok := h.subject(w, r)
	if !ok {
		return
	}
	proposals, err := h.service.ListProposals(r.Context(), subject.AccountID, subject.DeviceID, strings.TrimSpace(r.PathValue("conversation_id")))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	result := make([]proposalResponse, 0, len(proposals))
	for _, proposal := range proposals {
		result = append(result, toProposalResponse(proposal))
	}
	writeData(w, r, http.StatusOK, result)
}

func (h mlsStateHandler) listRoster(w http.ResponseWriter, r *http.Request) {
	subject, ok := h.subject(w, r)
	if !ok {
		return
	}
	entries, err := h.service.ListDeviceRoster(r.Context(), subject.AccountID, strings.TrimSpace(r.PathValue("conversation_id")))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, entries)
}

func (h mlsStateHandler) claim(w http.ResponseWriter, r *http.Request) {
	subject, ok := h.subject(w, r)
	if !ok {
		return
	}
	deliveries, err := h.service.ClaimWelcome(r.Context(), subject.AccountID, subject.DeviceID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	result := make([]welcomeResponse, 0, len(deliveries))
	for _, d := range deliveries {
		result = append(result, welcomeResponse{ID: d.ID, ConversationID: d.ConversationID, Epoch: d.Epoch, Welcome: base64.RawStdEncoding.EncodeToString(d.WelcomeData), CreatedAt: d.CreatedAt})
	}
	writeData(w, r, http.StatusOK, result)
}
func (h mlsStateHandler) subject(w http.ResponseWriter, r *http.Request) (authenticatedSubject, bool) {
	subject, err := authenticatedSubjectFromContext(r.Context())
	if err != nil {
		writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
		return authenticatedSubject{}, false
	}
	return subject, true
}
func (h mlsStateHandler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, mlsstate.ErrInvalidCommit), errors.Is(err, mlsstate.ErrInvalidWelcome), errors.Is(err, mlsstate.ErrInvalidProposal):
		writeError(w, r, http.StatusBadRequest, "invalid_request", "invalid MLS state request")
	case errors.Is(err, mlsstate.ErrNotFound), errors.Is(err, mlsstate.ErrNotAdministrator):
		writeError(w, r, http.StatusNotFound, "not_found", "resource not found")
	case errors.Is(err, mlsstate.ErrEpochConflict):
		writeError(w, r, http.StatusConflict, "epoch_conflict", "MLS epoch conflicts with current state")
	case errors.Is(err, mlsstate.ErrRosterConflict):
		writeError(w, r, http.StatusConflict, "roster_conflict", "MLS device roster conflicts with current state")
	case errors.Is(err, mlsstate.ErrProposalConflict):
		writeError(w, r, http.StatusConflict, "proposal_conflict", "MLS proposal conflicts with current state")
	default:
		writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
	}
}
func decodeMLSStateRequest(w http.ResponseWriter, r *http.Request, destination any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxMLSStateRequestBodyBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil || decoder.Decode(&struct{}{}) != io.EOF {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "invalid request body")
		return false
	}
	return true
}
func toProposalResponse(proposal mlsstate.Proposal) proposalResponse {
	return proposalResponse{ID: proposal.ID, ConversationID: proposal.ConversationID, AuthorAccountID: proposal.AuthorAccountID, AuthorDeviceID: proposal.AuthorDeviceID, BaseEpoch: proposal.BaseEpoch, Proposal: base64.RawStdEncoding.EncodeToString(proposal.Data), CreatedAt: proposal.CreatedAt}
}
func toGroupStateResponse(state mlsstate.GroupState) groupStateResponse {
	return groupStateResponse{ConversationID: state.ConversationID, Epoch: state.Epoch, GroupInfo: base64.RawStdEncoding.EncodeToString(state.GroupInfo), CommitData: base64.RawStdEncoding.EncodeToString(state.CommitData), CommittedAt: state.CommittedAt}
}
