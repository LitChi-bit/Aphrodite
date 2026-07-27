package httpapi

import (
	"log/slog"
	"net/http"
	"time"
)

type Server struct {
	handler http.Handler
	logger  *slog.Logger
}

func NewServer(logger *slog.Logger) *Server {
	server := &Server{logger: logger}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", server.health)
	mux.HandleFunc("GET /v1/health", server.health)
	mux.HandleFunc("/", server.notFound)
	server.handler = withRequestID(recoverPanic(logger, mux))
	return server
}

func (s *Server) Handler() http.Handler {
	return s.handler
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeData(w, r, http.StatusOK, map[string]any{
		"status": "ok",
		"time":   time.Now().UTC().Format(time.RFC3339),
	})
}

func (s *Server) notFound(w http.ResponseWriter, r *http.Request) {
	writeError(w, r, http.StatusNotFound, "route_not_found", "route not found")
}

func recoverPanic(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recovered := recover(); recovered != nil {
				logger.Error("request panic", "request_id", RequestID(r.Context()))
				writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}
