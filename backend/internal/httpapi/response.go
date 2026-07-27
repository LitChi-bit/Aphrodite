package httpapi

import (
	"encoding/json"
	"net/http"
)

type Meta struct {
	NextCursor *string `json:"next_cursor"`
}

type Envelope struct {
	RequestID string `json:"request_id"`
	Data      any    `json:"data"`
	Meta      Meta   `json:"meta"`
}

type ErrorBody struct {
	Code    string         `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details,omitempty"`
}

type ErrorEnvelope struct {
	RequestID string    `json:"request_id"`
	Error     ErrorBody `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeData(w http.ResponseWriter, r *http.Request, status int, data any) {
	writeJSON(w, status, Envelope{
		RequestID: RequestID(r.Context()),
		Data:      data,
		Meta:      Meta{},
	})
}

func writeError(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	writeJSON(w, status, ErrorEnvelope{
		RequestID: RequestID(r.Context()),
		Error: ErrorBody{
			Code:    code,
			Message: message,
		},
	})
}
