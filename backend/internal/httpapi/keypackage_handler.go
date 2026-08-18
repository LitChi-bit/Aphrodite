package httpapi

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/keypackage"
)

const maxKeyPackageRequestBodyBytes = 2 << 20

type KeyPackageService interface {
	Publish(ctx context.Context, accountID, deviceID string, items []keypackage.Publish) error
	ListAvailable(ctx context.Context, accountID string, limit int, now time.Time) ([]keypackage.KeyPackage, error)
	Claim(ctx context.Context, targetAccountID, requesterAccountID, requesterDeviceID, requesterSessionID string, limit int, now time.Time) ([]keypackage.KeyPackage, error)
}

type keyPackageHandler struct {
	service       KeyPackageService
	authenticator AccessTokenAuthenticator
	verifier      auth.AccessTokenVerifier
	now           func() time.Time
	newID         func() (string, error)
}

type publishKeyPackagesRequest struct {
	KeyPackages []publishKeyPackageRequest `json:"key_packages"`
}

type publishKeyPackageRequest struct {
	Ciphersuite string    `json:"ciphersuite"`
	KeyPackage  string    `json:"key_package"`
	Signature   string    `json:"signature"`
	ExpiresAt   time.Time `json:"expires_at"`
}

type keyPackageAvailabilityResponse struct {
	ID          string    `json:"id"`
	DeviceID    string    `json:"device_id"`
	Ciphersuite string    `json:"ciphersuite"`
	ExpiresAt   time.Time `json:"expires_at"`
}

type claimedKeyPackageResponse struct {
	ID          string    `json:"id"`
	DeviceID    string    `json:"device_id"`
	Ciphersuite string    `json:"ciphersuite"`
	KeyPackage  string    `json:"key_package"`
	Signature   string    `json:"signature"`
	ExpiresAt   time.Time `json:"expires_at"`
}

func (handler keyPackageHandler) register(mux *http.ServeMux) {
	mux.HandleFunc("PUT /v1/mls/key-packages", requireAccessToken(handler.authenticator, handler.verifier, handler.publish))
	mux.HandleFunc("GET /v1/accounts/{account_id}/mls/key-packages", requireAccessToken(handler.authenticator, handler.verifier, handler.list))
	mux.HandleFunc("POST /v1/accounts/{account_id}/mls/key-packages:claim", requireAccessToken(handler.authenticator, handler.verifier, handler.claim))
	mux.HandleFunc("/v1/mls/key-packages", methodNotAllowed(http.MethodPut))
	mux.HandleFunc("/v1/accounts/{account_id}/mls/key-packages", methodNotAllowed(http.MethodGet))
	mux.HandleFunc("/v1/accounts/{account_id}/mls/key-packages:claim", methodNotAllowed(http.MethodPost))
}

func (handler keyPackageHandler) publish(w http.ResponseWriter, r *http.Request) {
	subject, ok := handler.subject(w, r)
	if !ok {
		return
	}
	request, ok := decodePublishKeyPackagesRequest(w, r)
	if !ok {
		return
	}
	items := make([]keypackage.Publish, 0, len(request.KeyPackages))
	for _, input := range request.KeyPackages {
		packageBytes, err := base64.RawStdEncoding.DecodeString(input.KeyPackage)
		if err != nil {
			writeError(w, r, http.StatusBadRequest, "invalid_request", "key_package must be base64")
			return
		}
		signature, err := base64.RawStdEncoding.DecodeString(input.Signature)
		if err != nil {
			writeError(w, r, http.StatusBadRequest, "invalid_request", "signature must be base64")
			return
		}
		id, err := handler.newID()
		if err != nil {
			writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
			return
		}
		items = append(items, keypackage.Publish{
			ID: id, Ciphersuite: input.Ciphersuite, Package: packageBytes, Signature: signature,
			CreatedAt: handler.now().UTC(), ExpiresAt: input.ExpiresAt.UTC(),
		})
	}
	if err := handler.service.Publish(r.Context(), subject.AccountID, subject.DeviceID, items); err != nil {
		handler.writeError(w, r, err)
		return
	}
	writeData(w, r, http.StatusCreated, map[string]int{"accepted": len(items)})
}

func (handler keyPackageHandler) list(w http.ResponseWriter, r *http.Request) {
	if _, ok := handler.subject(w, r); !ok {
		return
	}
	accountID, limit, ok := handler.accountAndLimit(w, r)
	if !ok {
		return
	}
	items, err := handler.service.ListAvailable(r.Context(), accountID, limit, handler.now().UTC())
	if err != nil {
		handler.writeError(w, r, err)
		return
	}
	response := make([]keyPackageAvailabilityResponse, 0, len(items))
	for _, item := range items {
		response = append(response, keyPackageAvailabilityResponse{ID: item.ID, DeviceID: item.DeviceID, Ciphersuite: item.Ciphersuite, ExpiresAt: item.ExpiresAt})
	}
	writeData(w, r, http.StatusOK, response)
}

func (handler keyPackageHandler) claim(w http.ResponseWriter, r *http.Request) {
	subject, ok := handler.subject(w, r)
	if !ok {
		return
	}
	accountID, limit, ok := handler.accountAndLimit(w, r)
	if !ok {
		return
	}
	items, err := handler.service.Claim(r.Context(), accountID, subject.AccountID, subject.DeviceID, subject.SessionID, limit, handler.now().UTC())
	if err != nil {
		handler.writeError(w, r, err)
		return
	}
	response := make([]claimedKeyPackageResponse, 0, len(items))
	for _, item := range items {
		response = append(response, claimedKeyPackageResponse{
			ID: item.ID, DeviceID: item.DeviceID, Ciphersuite: item.Ciphersuite,
			KeyPackage: base64.RawStdEncoding.EncodeToString(item.Package),
			Signature:  base64.RawStdEncoding.EncodeToString(item.Signature), ExpiresAt: item.ExpiresAt,
		})
	}
	writeData(w, r, http.StatusOK, response)
}

func (handler keyPackageHandler) subject(w http.ResponseWriter, r *http.Request) (authenticatedSubject, bool) {
	subject, err := authenticatedSubjectFromContext(r.Context())
	if err != nil {
		writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
		return authenticatedSubject{}, false
	}
	return subject, true
}

func (handler keyPackageHandler) accountAndLimit(w http.ResponseWriter, r *http.Request) (string, int, bool) {
	accountID := strings.TrimSpace(r.PathValue("account_id"))
	if accountID == "" {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "account_id is required")
		return "", 0, false
	}
	limit := 1
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || keypackage.ValidateLimit(parsed) != nil {
			writeError(w, r, http.StatusBadRequest, "invalid_request", "limit must be between 1 and 20")
			return "", 0, false
		}
		limit = parsed
	}
	return accountID, limit, true
}

func (handler keyPackageHandler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, keypackage.ErrInvalidKeyPackage) || errors.Is(err, keypackage.ErrInvalidLimit) {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "invalid key package request")
		return
	}
	writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
}

func decodePublishKeyPackagesRequest(w http.ResponseWriter, r *http.Request) (publishKeyPackagesRequest, bool) {
	r.Body = http.MaxBytesReader(w, r.Body, maxKeyPackageRequestBodyBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var request publishKeyPackagesRequest
	if err := decoder.Decode(&request); err != nil || decoder.Decode(&struct{}{}) != io.EOF {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "invalid request body")
		return publishKeyPackagesRequest{}, false
	}
	return request, true
}
