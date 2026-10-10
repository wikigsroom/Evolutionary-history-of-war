package main

import (
	"context"
	"net"
	"net/http"
	"sync"
	"time"
)

type rateBucket struct {
	tokens float64
	at     time.Time
}
type rateGate struct {
	mu      sync.Mutex
	buckets map[string]rateBucket
}

func (g *rateGate) allow(key string, rate, burst float64) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	now := time.Now()
	b, exists := g.buckets[key]
	if !exists {
		if len(g.buckets) >= 10000 {
			for k, v := range g.buckets {
				if now.Sub(v.at) > 5*time.Minute {
					delete(g.buckets, k)
				}
			}
			if len(g.buckets) >= 10000 {
				return false
			}
		}
		b = rateBucket{tokens: burst, at: now}
	}
	b.tokens += now.Sub(b.at).Seconds() * rate
	if b.tokens > burst {
		b.tokens = burst
	}
	b.at = now
	allowed := b.tokens >= 1
	if allowed {
		b.tokens--
	}
	g.buckets[key] = b
	return allowed
}

func (s *Server) limited(next http.Handler) http.Handler {
	gate := &rateGate{buckets: map[string]rateBucket{}}
	slots := make(chan struct{}, 64)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			host = r.RemoteAddr
		}
		if s.trustProxy && net.ParseIP(host).IsLoopback() {
			if ip := net.ParseIP(r.Header.Get("X-Real-IP")); ip != nil {
				host = ip.String()
			}
		}
		rate, burst := 80.0, 160.0
		key := digest([]byte(host))
		if r.URL.Path == "/v1/auth/guest" || r.URL.Path == "/v1/auth/refresh" {
			rate = 2
			burst = 40
			key += "-auth"
		}
		if !gate.allow(key, rate, burst) {
			errorResponse(w, failure("RATE_LIMITED", 429))
			return
		}
		select {
		case slots <- struct{}{}:
			defer func() { <-slots }()
		default:
			errorResponse(w, failure("SERVER_BUSY", 503))
			return
		}
		next.ServeHTTP(w, r)
	})
}

type boundedListener struct {
	net.Listener
	ctx   context.Context
	slots chan struct{}
}
type countedConn struct {
	net.Conn
	once    sync.Once
	release func()
}

func (c *countedConn) Close() error { err := c.Conn.Close(); c.once.Do(c.release); return err }
func (l *boundedListener) Accept() (net.Conn, error) {
	select {
	case l.slots <- struct{}{}:
	case <-l.ctx.Done():
		return nil, net.ErrClosed
	}
	conn, err := l.Listener.Accept()
	if err != nil {
		<-l.slots
		return nil, err
	}
	return &countedConn{Conn: conn, release: func() { <-l.slots }}, nil
}
