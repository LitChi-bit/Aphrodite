package main

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/jackc/pgx/v5/pgxpool"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/chat"
	"aphrodite/backend/internal/config"
	"aphrodite/backend/internal/httpapi"
	"aphrodite/backend/internal/keypackage"
	"aphrodite/backend/internal/mlsstate"
)

func accessTokenPrivateKey(encoded string) (ed25519.PrivateKey, error) {
	value := strings.TrimSpace(encoded)
	if value == "" {
		return nil, errors.New("APHRODITE_ACCESS_TOKEN_PRIVATE_KEY is required")
	}
	privateKey, err := base64.StdEncoding.Strict().DecodeString(value)
	if err != nil || len(privateKey) != ed25519.PrivateKeySize {
		return nil, fmt.Errorf("APHRODITE_ACCESS_TOKEN_PRIVATE_KEY must be base64 Ed25519 private key")
	}
	return ed25519.PrivateKey(privateKey), nil
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		logger.Error("invalid configuration", "error", err)
		os.Exit(1)
	}

	if strings.TrimSpace(cfg.DatabaseURL) == "" {
		logger.Error("invalid configuration", "error", "APHRODITE_DATABASE_URL is required")
		os.Exit(1)
	}
	database, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		logger.Error("create database pool", "error", err)
		os.Exit(1)
	}
	defer database.Close()
	if err := database.Ping(context.Background()); err != nil {
		logger.Error("connect database", "error", err)
		os.Exit(1)
	}

	privateKey, err := accessTokenPrivateKey(cfg.AccessTokenPrivateKeyBase64)
	if err != nil {
		logger.Error("invalid access token signing key", "error", err)
		os.Exit(1)
	}
	issuer, err := auth.NewEd25519AccessTokenIssuer(privateKey, nil)
	if err != nil {
		logger.Error("create access token issuer", "error", err)
		os.Exit(1)
	}
	verifier, err := auth.NewEd25519AccessTokenVerifier(privateKey.Public().(ed25519.PublicKey), nil)
	if err != nil {
		logger.Error("create access token verifier", "error", err)
		os.Exit(1)
	}
	repository := auth.NewPostgresRepository(database)
	chatRepository := chat.NewPostgresRepository(database)
	keyPackageRepository := keypackage.NewPostgresRepository(database)
	mlsStateRepository := mlsstate.NewPostgresRepository(database)
	service, err := auth.NewService(auth.Dependencies{
		Accounts: repository, Devices: repository, Challenges: repository, Sessions: repository,
		Passwords: auth.BcryptPasswordVerifier{}, Hasher: auth.SHA256TokenHasher{},
		Credentials: auth.SecureCredentialGenerator{}, IDs: auth.RandomIDGenerator{}, AccessTokens: issuer,
	})
	if err != nil {
		logger.Error("create auth service", "error", err)
		os.Exit(1)
	}

	api := httpapi.NewServer(
		logger,
		httpapi.WithAuthService(service),
		httpapi.WithDeviceService(service, verifier),
		httpapi.WithChatService(chatRepository, service, verifier),
		httpapi.WithKeyPackageService(keyPackageRepository, service, verifier),
		httpapi.WithMLSStateService(mlsStateRepository, service, verifier),
	)
	server := &http.Server{
		Addr:         cfg.Address(),
		Handler:      api.Handler(),
		ReadTimeout:  cfg.ReadTimeout,
		WriteTimeout: cfg.WriteTimeout,
		IdleTimeout:  cfg.IdleTimeout,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		logger.Info("api server started", "address", server.Addr, "environment", cfg.Environment)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("api server stopped unexpectedly", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}
	logger.Info("api server stopped")
}
