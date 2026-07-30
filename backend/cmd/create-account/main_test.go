package main

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"

	"golang.org/x/crypto/bcrypt"
)

type recordingAccountInserter struct {
	account accountRecord
	err     error
	calls   int
}

func (inserter *recordingAccountInserter) InsertAccount(_ context.Context, account accountRecord) error {
	inserter.calls++
	inserter.account = account
	return inserter.err
}

func validArguments() []string {
	return []string{
		"-username", "example_user", "-email", "user@example.invalid", "-display-name", "Example User",
		"-target", "example@127.0.0.1:5432/aphrodite_test", "-confirm", executionConfirmation,
	}
}

func testDatabaseURL() string {
	return "postgres://example:example@127.0.0.1:5432/aphrodite_test?sslmode=disable"
}

func TestRunCreatesAccountWithBcryptHash(t *testing.T) {
	inserter := &recordingAccountInserter{}
	var output bytes.Buffer
	password := "example-password-2026"
	err := run(context.Background(), validArguments(), strings.NewReader(password+"\n"), &output,
		func(key string) string {
			if key != databaseURLEnvironment {
				t.Fatalf("unexpected environment key %q", key)
			}
			return testDatabaseURL()
		}, inserter)
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if inserter.calls != 1 {
		t.Fatalf("insert calls = %d, want 1", inserter.calls)
	}
	if inserter.account.Username != "example_user" || inserter.account.Email != "user@example.invalid" || inserter.account.DisplayName != "Example User" {
		t.Fatalf("unexpected account: %#v", inserter.account)
	}
	if inserter.account.ID == "" || inserter.account.CreatedAt.IsZero() {
		t.Fatalf("missing generated fields: %#v", inserter.account)
	}
	if inserter.account.PasswordHash == password || bcrypt.CompareHashAndPassword([]byte(inserter.account.PasswordHash), []byte(password)) != nil {
		t.Fatal("password was not bcrypt hashed")
	}
	if strings.Contains(output.String(), password) || strings.Contains(output.String(), inserter.account.PasswordHash) {
		t.Fatalf("output exposed password material: %q", output.String())
	}
}

func TestRunRejectsWrongDatabaseTargetBeforeReadingPassword(t *testing.T) {
	inserter := &recordingAccountInserter{}
	arguments := validArguments()
	arguments[7] = "example@other-host:5432/aphrodite_test"
	var output bytes.Buffer
	err := run(context.Background(), arguments, strings.NewReader("must-not-be-read\n"), &output,
		func(string) string { return testDatabaseURL() }, inserter)
	if err == nil || !strings.Contains(err.Error(), "database target mismatch") {
		t.Fatalf("run() error = %v", err)
	}
	if strings.Contains(output.String(), "Password:") || inserter.calls != 0 {
		t.Fatalf("password was read or insert attempted: output=%q calls=%d", output.String(), inserter.calls)
	}
}

func TestRunRequiresExplicitActionConfirmation(t *testing.T) {
	inserter := &recordingAccountInserter{}
	arguments := validArguments()
	arguments[9] = "WRONG"
	err := run(context.Background(), arguments, strings.NewReader("example-password-2026\n"), &bytes.Buffer{},
		func(string) string { return testDatabaseURL() }, inserter)
	if err == nil || !strings.Contains(err.Error(), "confirm must equal") || inserter.calls != 0 {
		t.Fatalf("run() error = %v calls=%d", err, inserter.calls)
	}
}

func TestRunPropagatesDuplicateAccountError(t *testing.T) {
	inserter := &recordingAccountInserter{err: errors.New("an account with that username already exists")}
	err := run(context.Background(), validArguments(), strings.NewReader("example-password-2026\n"), &bytes.Buffer{},
		func(string) string { return testDatabaseURL() }, inserter)
	if err == nil || !strings.Contains(err.Error(), "already exists") {
		t.Fatalf("run() error = %v", err)
	}
}

func TestValidateNonSecretInput(t *testing.T) {
	valid := accountInput{
		Username: "example_user", Email: "user@example.invalid", DisplayName: "Example User",
		Target: "example@127.0.0.1:5432/aphrodite_test", ConfirmAction: executionConfirmation,
	}
	tests := []struct {
		name   string
		mutate func(*accountInput)
	}{
		{name: "short username", mutate: func(input *accountInput) { input.Username = "ab" }},
		{name: "username control", mutate: func(input *accountInput) { input.Username = "abc\nadmin" }},
		{name: "display control", mutate: func(input *accountInput) { input.DisplayName = "Example\x1bUser" }},
		{name: "uppercase email", mutate: func(input *accountInput) { input.Email = "User@example.invalid" }},
		{name: "empty local email", mutate: func(input *accountInput) { input.Email = "@example.invalid" }},
		{name: "empty domain email", mutate: func(input *accountInput) { input.Email = "user@" }},
		{name: "multiple at email", mutate: func(input *accountInput) { input.Email = "user@@example.invalid" }},
		{name: "missing target", mutate: func(input *accountInput) { input.Target = "" }},
		{name: "wrong confirmation", mutate: func(input *accountInput) { input.ConfirmAction = "wrong" }},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			input := valid
			test.mutate(&input)
			if err := validateNonSecretInput(input); err == nil {
				t.Fatal("validateNonSecretInput() error = nil")
			}
		})
	}
}

func TestPasswordLengthBoundaries(t *testing.T) {
	for _, test := range []struct {
		password string
		wantErr  bool
	}{
		{password: strings.Repeat("a", 11), wantErr: true},
		{password: strings.Repeat("a", 12)},
		{password: strings.Repeat("a", 72)},
		{password: strings.Repeat("a", 73), wantErr: true},
	} {
		inserter := &recordingAccountInserter{}
		err := run(context.Background(), validArguments(), strings.NewReader(test.password+"\n"), &bytes.Buffer{},
			func(string) string { return testDatabaseURL() }, inserter)
		if (err != nil) != test.wantErr {
			t.Fatalf("password bytes=%d error=%v wantErr=%v", len(test.password), err, test.wantErr)
		}
	}
}

func TestDatabaseTargetFromURL(t *testing.T) {
	target, err := databaseTargetFromURL("postgresql://example:example@LOCALHOST/aphrodite_test?sslmode=disable")
	if err != nil || target.Fingerprint() != "example@localhost:5432/aphrodite_test" {
		t.Fatalf("databaseTargetFromURL() = %#v, %v", target, err)
	}
	invalid := []string{
		"", "https://example@localhost/aphrodite_test", "postgres://localhost/aphrodite_test",
		"postgres://example@localhost", "postgres://example@localhost/a/b",
		"postgres://example@localhost/aphrodite_test?search_path=other",
		"postgres://example@localhost/aphrodite_test?options=-csearch_path%3Dother",
		"postgres://example@localhost/aphrodite_test?dbname=other",
		"postgres://example@localhost/aphrodite_test?database=other",
		"postgres://example@localhost/aphrodite_test?host=other",
		"postgres://example@localhost/aphrodite_test?port=6543",
		"postgres://example@localhost/aphrodite_test?user=other",
		"postgres://example@localhost/aphrodite_test?connect_timeout=5",
		"postgres://example%0Aadmin@localhost/aphrodite_test",
		"postgres://example@localhost/aphrodite%1Btest",
	}
	for _, value := range invalid {
		if _, err := databaseTargetFromURL(value); err == nil {
			t.Fatalf("databaseTargetFromURL(%q) error = nil", value)
		}
	}
}
