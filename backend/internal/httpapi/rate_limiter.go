package httpapi

import (
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

type RateLimiter interface {
	Allow(scope, key string, now time.Time) (allowed bool, retryAfter time.Duration)
}

type fixedWindowRateLimiter struct {
	mu       sync.Mutex
	windows  map[string]rateWindow
	limit    int
	interval time.Duration
}

type rateWindow struct {
	count     int
	startedAt time.Time
}

func newFixedWindowRateLimiter(limit int, interval time.Duration) *fixedWindowRateLimiter {
	return &fixedWindowRateLimiter{
		windows:  make(map[string]rateWindow),
		limit:    limit,
		interval: interval,
	}
}

func (limiter *fixedWindowRateLimiter) Allow(scope, key string, now time.Time) (bool, time.Duration) {
	limiter.mu.Lock()
	defer limiter.mu.Unlock()

	limiter.pruneExpired(now)
	windowKey := scope + "\x00" + key
	window := limiter.windows[windowKey]
	if window.startedAt.IsZero() || !now.Before(window.startedAt.Add(limiter.interval)) {
		limiter.windows[windowKey] = rateWindow{count: 1, startedAt: now}
		return true, 0
	}
	if window.count >= limiter.limit {
		return false, window.startedAt.Add(limiter.interval).Sub(now)
	}
	window.count++
	limiter.windows[windowKey] = window
	return true, 0
}

func (limiter *fixedWindowRateLimiter) pruneExpired(now time.Time) {
	for key, window := range limiter.windows {
		if !now.Before(window.startedAt.Add(limiter.interval)) {
			delete(limiter.windows, key)
		}
	}
}

func rateLimit(limiter RateLimiter, scope string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		allowed, retryAfter := limiter.Allow(scope, clientAddress(r), time.Now().UTC())
		if !allowed {
			seconds := int((retryAfter + time.Second - 1).Seconds())
			if seconds < 1 {
				seconds = 1
			}
			w.Header().Set("Retry-After", strconv.Itoa(seconds))
			writeError(w, r, http.StatusTooManyRequests, "rate_limited", "too many requests")
			return
		}
		next(w, r)
	}
}

func clientAddress(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	if strings.TrimSpace(r.RemoteAddr) != "" {
		return r.RemoteAddr
	}
	return "unknown"
}
