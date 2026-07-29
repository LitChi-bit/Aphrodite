package httpapi

import (
	"log/slog"
	"net/http"
	"time"

	"aphrodite/backend/internal/auth"
)

type Server struct {
	handler http.Handler
	logger  *slog.Logger
}

type Option func(*serverOptions)

type serverOptions struct {
	authService      AuthService
	deviceService    DeviceService
	accessVerifier   auth.AccessTokenVerifier
	challengeLimiter RateLimiter
	tokenLimiter     RateLimiter
}

func WithAuthService(service AuthService) Option {
	return func(options *serverOptions) {
		options.authService = service
	}
}

func WithDeviceService(service DeviceService, verifier auth.AccessTokenVerifier) Option {
	return func(options *serverOptions) {
		options.deviceService = service
		options.accessVerifier = verifier
	}
}

func WithAuthRateLimiters(challengeLimiter, tokenLimiter RateLimiter) Option {
	return func(options *serverOptions) {
		options.challengeLimiter = challengeLimiter
		options.tokenLimiter = tokenLimiter
	}
}

func NewServer(logger *slog.Logger, options ...Option) *Server {
	configuration := serverOptions{
		challengeLimiter: newFixedWindowRateLimiter(10, time.Minute),
		tokenLimiter:     newFixedWindowRateLimiter(30, time.Minute),
	}
	for _, option := range options {
		option(&configuration)
	}
	if configuration.challengeLimiter == nil {
		configuration.challengeLimiter = newFixedWindowRateLimiter(10, time.Minute)
	}
	if configuration.tokenLimiter == nil {
		configuration.tokenLimiter = newFixedWindowRateLimiter(30, time.Minute)
	}
	server := &Server{logger: logger}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", server.health)
	mux.HandleFunc("GET /v1/health", server.health)
	if configuration.authService != nil {
		authHandler{
			service:          configuration.authService,
			challengeLimiter: configuration.challengeLimiter,
			tokenLimiter:     configuration.tokenLimiter,
		}.register(mux)
	}
	if configuration.deviceService != nil && configuration.accessVerifier != nil {
		deviceHandler{service: configuration.deviceService, verifier: configuration.accessVerifier}.register(mux)
	}
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
