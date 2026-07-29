package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"aphrodite/backend/internal/auth"
)

type DeviceService interface {
	AccessTokenAuthenticator
	ListDevices(ctx context.Context, accountID string) ([]auth.Device, error)
	RevokeDevice(ctx context.Context, accountID, deviceID string) error
}

type deviceHandler struct {
	service  DeviceService
	verifier auth.AccessTokenVerifier
}

type deviceResponse struct {
	ID         string     `json:"id"`
	Name       string     `json:"name"`
	Platform   string     `json:"platform"`
	Current    bool       `json:"current"`
	Revoked    bool       `json:"revoked"`
	LastSeenAt *time.Time `json:"last_seen_at"`
	CreatedAt  time.Time  `json:"created_at"`
}

func (handler deviceHandler) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /v1/devices", requireAccessToken(handler.service, handler.verifier, handler.list))
	mux.HandleFunc("DELETE /v1/devices/{device_id}", requireAccessToken(handler.service, handler.verifier, handler.revoke))
	mux.HandleFunc("/v1/devices", methodNotAllowed(http.MethodGet))
	mux.HandleFunc("/v1/devices/{device_id}", methodNotAllowed(http.MethodDelete))
}

func (handler deviceHandler) list(w http.ResponseWriter, r *http.Request) {
	subject, err := authenticatedSubjectFromContext(r.Context())
	if err != nil {
		writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
		return
	}
	devices, err := handler.service.ListDevices(r.Context(), subject.AccountID)
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
		return
	}
	response := make([]deviceResponse, 0, len(devices))
	for _, device := range devices {
		response = append(response, deviceResponse{
			ID: device.ID, Name: device.Name, Platform: device.Platform,
			Current: device.ID == subject.DeviceID, Revoked: device.IsRevoked(),
			LastSeenAt: device.LastSeenAt, CreatedAt: device.CreatedAt,
		})
	}
	writeData(w, r, http.StatusOK, response)
}

func (handler deviceHandler) revoke(w http.ResponseWriter, r *http.Request) {
	subject, err := authenticatedSubjectFromContext(r.Context())
	if err != nil {
		writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
		return
	}
	deviceID := r.PathValue("device_id")
	if deviceID == "" {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "device_id is required")
		return
	}
	if err := handler.service.RevokeDevice(r.Context(), subject.AccountID, deviceID); err != nil {
		if errors.Is(err, auth.ErrDeviceNotFound) {
			writeError(w, r, http.StatusNotFound, "device_not_found", "device not found")
			return
		}
		writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
