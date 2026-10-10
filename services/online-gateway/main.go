package main

import (
	"context"
	"flag"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

type Server struct {
	store                    *Store
	rules                    *Rules
	godot, project, instance string
	ctx                      context.Context
	cancel                   context.CancelFunc
	mu                       sync.Mutex
	runtimes                 map[string]bool
	maxMatches               int
	draining                 atomic.Bool
	drainFile                string
	trustProxy               bool
}

func main() {
	listen := flag.String("listen", "127.0.0.1:28187", "HTTP listen address (put TLS reverse proxy in front)")
	project := flag.String("project", "../../godot", "Godot simulation project")
	godot := flag.String("godot", "../../godot/toolchain/editor/Godot_v4.7.2-stable_win64_console.exe", "native Godot executable")
	maxMatches := flag.Int("max-matches", 10, "capacity gate; raise only after load tests")
	drainFile := flag.String("drain-file", "", "presence of this local file disables new matches")
	trustProxy := flag.Bool("trust-local-proxy", false, "trust X-Real-IP only from a loopback reverse proxy")
	flag.Parse()
	if *maxMatches < 1 || *maxMatches > 500 {
		log.Fatal("max-matches must be between 1 and 500")
	}
	if os.Getenv("EPOCH_DATABASE_URL") == "" {
		log.Fatal("EPOCH_DATABASE_URL is required; credentials are never logged")
	}
	absProject, err := filepath.Abs(*project)
	if err != nil {
		log.Fatal(err)
	}
	absGodot, err := filepath.Abs(*godot)
	if err != nil {
		log.Fatal(err)
	}
	rules, err := loadRules(absProject)
	if err != nil {
		log.Fatal(err)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	store, err := openStore(ctx, os.Getenv("EPOCH_DATABASE_URL"))
	if err != nil {
		log.Fatal(err)
	}
	defer store.pool.Close()
	s := &Server{store: store, rules: rules, godot: absGodot, project: absProject, instance: identifier(), ctx: ctx, cancel: cancel, runtimes: map[string]bool{}, maxMatches: *maxMatches}
	s.drainFile = *drainFile
	s.trustProxy = *trustProxy
	s.updateDrain()
	go s.supervise()
	go s.lobbyMaintenance()
	go s.retentionLoop()
	h := &http.Server{Addr: *listen, Handler: s.limited(s.routes()), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16384}
	go func() {
		<-ctx.Done()
		s.draining.Store(true)
		shutdownCtx, c := context.WithTimeout(context.Background(), 5*time.Second)
		defer c()
		_ = h.Shutdown(shutdownCtx)
	}()
	log.Printf("Epoch Rush online gateway listening at %s; capacity=%d", *listen, *maxMatches)
	listener, e := net.Listen("tcp", *listen)
	if e != nil {
		log.Fatal(e)
	}
	bounded := &boundedListener{Listener: listener, ctx: ctx, slots: make(chan struct{}, 512)}
	if err = h.Serve(bounded); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
