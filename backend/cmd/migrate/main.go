package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"aphrodite/backend/internal/migrations"
)

const baselineConfirmation = "BASELINE_EXISTING_SCHEMA"

func main() {
	if err := run(context.Background(), os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "migration failed:", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string) error {
	flags := flag.NewFlagSet("migrate", flag.ContinueOnError)
	directory := flags.String("dir", "migrations", "migration directory")
	baseline := flags.Bool("baseline", false, "record existing schema without executing migrations")
	confirmation := flags.String("confirm", "", "required confirmation for baseline")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected positional arguments")
	}
	if *baseline && *confirmation != baselineConfirmation {
		return fmt.Errorf("baseline requires -confirm %s", baselineConfirmation)
	}
	databaseURL := strings.TrimSpace(os.Getenv("APHRODITE_DATABASE_URL"))
	if databaseURL == "" {
		return errors.New("APHRODITE_DATABASE_URL is required")
	}
	loaded, err := migrations.Load(*directory)
	if err != nil {
		return err
	}
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return fmt.Errorf("create database pool: %w", err)
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		return fmt.Errorf("connect database: %w", err)
	}
	runner := migrations.NewRunner(pool)
	if *baseline {
		if err := runner.Baseline(ctx, loaded); err != nil {
			return err
		}
		fmt.Printf("baselined %d migrations\n", len(loaded))
		return nil
	}
	if err := runner.Apply(ctx, loaded); err != nil {
		return err
	}
	fmt.Printf("migration check complete: %d known migrations\n", len(loaded))
	return nil
}
