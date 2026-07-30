package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/mail"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/term"

	"aphrodite/backend/internal/auth"
)

const (
	databaseURLEnvironment = "APHRODITE_DATABASE_URL"
	executionConfirmation  = "CREATE_ACCOUNT"
	commandTimeout         = 30 * time.Second
)

var usernamePattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.-]{2,63}$`)

type accountInput struct {
	Username      string
	Email         string
	DisplayName   string
	Password      string
	Target        string
	ConfirmAction string
}

type databaseTarget struct {
	User     string
	Host     string
	Port     string
	Database string
}

func (target databaseTarget) Fingerprint() string {
	return fmt.Sprintf("%s@%s:%s/%s", target.User, target.Host, target.Port, target.Database)
}

type accountRecord struct {
	ID           string
	Username     string
	Email        string
	DisplayName  string
	PasswordHash string
	CreatedAt    time.Time
}

type accountInserter interface {
	InsertAccount(context.Context, accountRecord) error
}

type postgresAccountInserter struct {
	pool *pgxpool.Pool
}

func (inserter postgresAccountInserter) InsertAccount(ctx context.Context, account accountRecord) error {
	_, err := inserter.pool.Exec(ctx, `INSERT INTO public.accounts
		(id, username, email, display_name, password_hash, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, 'active', $6, $6)`,
		account.ID, account.Username, account.Email, account.DisplayName, account.PasswordHash, account.CreatedAt)
	if err == nil {
		return nil
	}
	var postgresError *pgconn.PgError
	if errors.As(err, &postgresError) && postgresError.Code == "23505" {
		switch postgresError.ConstraintName {
		case "accounts_username_unique_ci":
			return errors.New("an account with that username already exists")
		case "accounts_email_unique":
			return errors.New("an account with that email already exists")
		default:
			return errors.New("account conflicts with an existing record")
		}
	}
	return fmt.Errorf("insert account: %w", err)
}

func main() {
	if err := run(context.Background(), os.Args[1:], os.Stdin, os.Stdout, os.Getenv, nil); err != nil {
		fmt.Fprintln(os.Stderr, "create account:", err)
		os.Exit(1)
	}
}

func run(
	ctx context.Context,
	arguments []string,
	stdin io.Reader,
	stdout io.Writer,
	getenv func(string) string,
	inserter accountInserter,
) error {
	flags := flag.NewFlagSet("create-account", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	username := flags.String("username", "", "account username")
	email := flags.String("email", "", "account email")
	displayName := flags.String("display-name", "", "account display name")
	targetConfirmation := flags.String("target", "", "expected database target user@host:port/database")
	actionConfirmation := flags.String("confirm", "", "required execution confirmation")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected positional arguments")
	}

	input := accountInput{
		Username: strings.TrimSpace(*username), Email: strings.TrimSpace(*email), DisplayName: strings.TrimSpace(*displayName),
		Target: strings.TrimSpace(*targetConfirmation), ConfirmAction: strings.TrimSpace(*actionConfirmation),
	}
	if err := validateNonSecretInput(input); err != nil {
		return err
	}

	databaseURL := strings.TrimSpace(getenv(databaseURLEnvironment))
	target, err := databaseTargetFromURL(databaseURL)
	if err != nil {
		return err
	}
	if target.Fingerprint() != input.Target {
		return fmt.Errorf("database target mismatch: expected %q", target.Fingerprint())
	}

	input.Password, err = readPassword(stdin, stdout)
	if err != nil {
		return err
	}
	if len(input.Password) < 12 || len(input.Password) > 72 {
		return errors.New("password must contain 12 to 72 bytes")
	}
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash password: %w", err)
	}
	id, err := (auth.RandomIDGenerator{}).NewID("account")
	if err != nil {
		return err
	}
	record := accountRecord{
		ID: id, Username: input.Username, Email: input.Email, DisplayName: input.DisplayName,
		PasswordHash: string(passwordHash), CreatedAt: time.Now().UTC(),
	}

	if inserter != nil {
		if err := inserter.InsertAccount(ctx, record); err != nil {
			return err
		}
	} else {
		databaseContext, cancel := context.WithTimeout(ctx, commandTimeout)
		defer cancel()
		pool, err := pgxpool.New(databaseContext, databaseURL)
		if err != nil {
			return fmt.Errorf("create database pool: %w", err)
		}
		defer pool.Close()
		if err := pool.Ping(databaseContext); err != nil {
			return fmt.Errorf("connect database: %w", err)
		}
		if err := (postgresAccountInserter{pool: pool}).InsertAccount(databaseContext, record); err != nil {
			return err
		}
	}

	fmt.Fprintf(stdout, "account created: id=%s username=%q target=%s\n", record.ID, record.Username, target.Fingerprint())
	return nil
}

func readPassword(stdin io.Reader, stdout io.Writer) (string, error) {
	fmt.Fprint(stdout, "Password: ")
	if file, ok := stdin.(*os.File); ok {
		if !term.IsTerminal(int(file.Fd())) {
			return "", errors.New("password input must be an interactive terminal")
		}
		password, err := term.ReadPassword(int(file.Fd()))
		fmt.Fprintln(stdout)
		if err != nil {
			return "", fmt.Errorf("read password: %w", err)
		}
		return string(password), nil
	}
	password, err := bufio.NewReader(stdin).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return "", fmt.Errorf("read password: %w", err)
	}
	return strings.TrimRight(password, "\r\n"), nil
}

func validateNonSecretInput(input accountInput) error {
	if !usernamePattern.MatchString(input.Username) {
		return errors.New("username must contain 3 to 64 ASCII letters, digits, dots, underscores, or hyphens and start with a letter or digit")
	}
	if count := utf8.RuneCountInString(input.DisplayName); count < 1 || count > 128 || containsControl(input.DisplayName) {
		return errors.New("display name must contain 1 to 128 characters without control characters")
	}
	if len(input.Email) > 254 || input.Email != strings.ToLower(input.Email) || containsControl(input.Email) {
		return errors.New("email must be a lowercase email address of at most 254 bytes")
	}
	address, err := mail.ParseAddress(input.Email)
	if err != nil || address.Address != input.Email || strings.Count(input.Email, "@") != 1 {
		return errors.New("email must be a lowercase email address of at most 254 bytes")
	}
	parts := strings.Split(input.Email, "@")
	if parts[0] == "" || parts[1] == "" || !strings.Contains(parts[1], ".") {
		return errors.New("email must include a non-empty local part and domain")
	}
	if input.Target == "" {
		return errors.New("target confirmation is required")
	}
	if input.ConfirmAction != executionConfirmation {
		return fmt.Errorf("confirm must equal %q", executionConfirmation)
	}
	return nil
}

func containsControl(value string) bool {
	for _, character := range value {
		if character < 0x20 || character == 0x7f {
			return true
		}
	}
	return false
}

func databaseTargetFromURL(databaseURL string) (databaseTarget, error) {
	if databaseURL == "" {
		return databaseTarget{}, fmt.Errorf("%s is required", databaseURLEnvironment)
	}
	parsed, err := url.Parse(databaseURL)
	if err != nil || (parsed.Scheme != "postgres" && parsed.Scheme != "postgresql") {
		return databaseTarget{}, fmt.Errorf("%s must be a PostgreSQL URL", databaseURLEnvironment)
	}
	if parsed.User == nil || parsed.User.Username() == "" || parsed.Hostname() == "" {
		return databaseTarget{}, fmt.Errorf("%s must include user and host", databaseURLEnvironment)
	}
	for key := range parsed.Query() {
		if key != "sslmode" {
			return databaseTarget{}, fmt.Errorf("%s query parameter %q is not allowed by this administrative command", databaseURLEnvironment, key)
		}
	}
	name := strings.TrimPrefix(parsed.EscapedPath(), "/")
	name, err = url.PathUnescape(name)
	if err != nil || name == "" || strings.Contains(name, "/") {
		return databaseTarget{}, fmt.Errorf("%s must include one database name", databaseURLEnvironment)
	}
	port := parsed.Port()
	if port == "" {
		port = "5432"
	}
	target := databaseTarget{User: parsed.User.Username(), Host: strings.ToLower(parsed.Hostname()), Port: port, Database: name}
	for _, component := range []string{target.User, target.Host, target.Port, target.Database} {
		if strings.TrimSpace(component) != component || containsControl(component) {
			return databaseTarget{}, fmt.Errorf("%s database target contains unsafe characters", databaseURLEnvironment)
		}
	}
	return target, nil
}

var _ accountInserter = postgresAccountInserter{}
