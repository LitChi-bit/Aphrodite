package auth

import (
	"os"
	"testing"
	"time"
)

func TestEqualBytes(t *testing.T) {
	tests := []struct {
		name  string
		left  []byte
		right []byte
		want  bool
	}{
		{name: "equal", left: []byte{1, 2, 3}, right: []byte{1, 2, 3}, want: true},
		{name: "different content", left: []byte{1, 2, 3}, right: []byte{1, 2, 4}, want: false},
		{name: "different lengths", left: []byte{1, 2}, right: []byte{1, 2, 0}, want: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := equalBytes(test.left, test.right); got != test.want {
				t.Fatalf("equalBytes() = %v, want %v", got, test.want)
			}
		})
	}
}

func TestMinTime(t *testing.T) {
	earlier := time.Date(2026, 7, 29, 10, 0, 0, 0, time.UTC)
	later := earlier.Add(time.Hour)
	if got := minTime(later, earlier); !got.Equal(earlier) {
		t.Fatalf("minTime() = %v, want %v", got, earlier)
	}
	if got := minTime(earlier, later); !got.Equal(earlier) {
		t.Fatalf("minTime() = %v, want %v", got, earlier)
	}
}

func TestPostgresRepositoryIntegration(t *testing.T) {
	if os.Getenv("APHRODITE_TEST_DATABASE_URL") == "" {
		t.Skip("requires APHRODITE_TEST_DATABASE_URL; no database connection attempted")
	}
	t.Skip("PostgreSQL integration scenarios require a migrated disposable database")
}
