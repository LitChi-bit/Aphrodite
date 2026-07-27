package httpapi

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthReturnsFrontendCompatibleEnvelope(t *testing.T) {
	server := NewServer(discardLogger())
	request := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	request.Header.Set(requestIDHeader, "request-example")
	response := httptest.NewRecorder()

	server.Handler().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d", response.Code)
	}
	if response.Header().Get(requestIDHeader) != "request-example" {
		t.Fatalf("request header = %q", response.Header().Get(requestIDHeader))
	}

	var envelope struct {
		RequestID string `json:"request_id"`
		Data      struct {
			Status string `json:"status"`
			Time   string `json:"time"`
		} `json:"data"`
		Meta Meta `json:"meta"`
	}
	if err := json.NewDecoder(response.Body).Decode(&envelope); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if envelope.RequestID != "request-example" || envelope.Data.Status != "ok" {
		t.Fatalf("unexpected envelope: %#v", envelope)
	}
	if envelope.Data.Time == "" {
		t.Fatal("health time must not be empty")
	}
}

func TestRequestIDIsGeneratedWhenMissing(t *testing.T) {
	server := NewServer(discardLogger())
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	response := httptest.NewRecorder()

	server.Handler().ServeHTTP(response, request)

	requestID := response.Header().Get(requestIDHeader)
	if requestID == "" {
		t.Fatal("X-Request-ID must be generated")
	}
	var envelope Envelope
	if err := json.NewDecoder(response.Body).Decode(&envelope); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if envelope.RequestID != requestID {
		t.Fatalf("body request_id = %q, header = %q", envelope.RequestID, requestID)
	}
}

func TestPanicRecoveryKeepsRequestID(t *testing.T) {
	requestIDMiddleware := withRequestID(recoverPanic(discardLogger(), http.HandlerFunc(
		func(http.ResponseWriter, *http.Request) {
			panic("example panic")
		},
	)))
	request := httptest.NewRequest(http.MethodGet, "/panic", nil)
	request.Header.Set(requestIDHeader, "request-example")
	response := httptest.NewRecorder()

	requestIDMiddleware.ServeHTTP(response, request)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d", response.Code)
	}
	var envelope ErrorEnvelope
	if err := json.NewDecoder(response.Body).Decode(&envelope); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if envelope.RequestID != "request-example" || envelope.Error.Code != "internal_error" {
		t.Fatalf("unexpected error envelope: %#v", envelope)
	}
}

func TestUnknownRouteReturnsStructuredError(t *testing.T) {
	server := NewServer(discardLogger())
	request := httptest.NewRequest(http.MethodGet, "/v1/missing", nil)
	response := httptest.NewRecorder()

	server.Handler().ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("status = %d", response.Code)
	}
	var envelope ErrorEnvelope
	if err := json.NewDecoder(response.Body).Decode(&envelope); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if envelope.RequestID == "" || envelope.Error.Code != "route_not_found" {
		t.Fatalf("unexpected error envelope: %#v", envelope)
	}
}

func discardLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}
