// Copyright 2026 The MathWorks, Inc.

package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

// envFlags collects repeatable --env KEY=VALUE flags.
type envFlags []string

func (e *envFlags) String() string { return strings.Join(*e, ",") }
func (e *envFlags) Set(v string) error {
	*e = append(*e, v)
	return nil
}

func main() {
	var (
		token       string
		envVars     envFlags
		idleTimeout time.Duration
		readyFile   string
		staticDir   string
	)

	flag.StringVar(&token, "token", "", "authentication token (--token or MATLAB_TERMINAL_TOKEN env var)")
	flag.Var(&envVars, "env", "environment variable in KEY=VALUE format (repeatable)")
	flag.DurationVar(&idleTimeout, "idle-timeout", 30*time.Second, "exit after this duration with no connections")
	flag.StringVar(&readyFile, "ready-file", "", "write PID/PORT to this file on startup (closed immediately)")
	flag.StringVar(&staticDir, "static-dir", "", "serve static files from this directory at /static/")
	flag.Parse()

	// Prefer env var over CLI flag to avoid leaking the token in the
	// process list (ps, tasklist, /proc/*/cmdline).
	if envToken := os.Getenv("MATLAB_TERMINAL_TOKEN"); envToken != "" {
		token = envToken
		os.Unsetenv("MATLAB_TERMINAL_TOKEN")
	}
	if token == "" {
		log.Fatal("--token or MATLAB_TERMINAL_TOKEN is required")
	}

	// Apply extra environment variables to the current process.
	// Child processes (PTY sessions) inherit them on all platforms.
	for _, e := range envVars {
		if k, v, ok := strings.Cut(e, "="); ok {
			os.Setenv(k, v)
		}
	}
	// Override TERM so PTY sessions get color support (harmless on Windows).
	os.Setenv("TERM", "xterm-256color")

	// Ensure UTF-8 locale for multi-byte character support (CJK, etc.).
	// Without this, shells may not process non-ASCII input correctly.
	if lang := os.Getenv("LANG"); lang == "" || lang == "C" || lang == "POSIX" {
		os.Setenv("LANG", "en_US.UTF-8")
	}
	if os.Getenv("LC_ALL") == "C" || os.Getenv("LC_ALL") == "POSIX" {
		os.Setenv("LC_ALL", "en_US.UTF-8")
	}

	// Detect default shell (platform-specific).
	shell := defaultShell()

	// Create session manager.
	manager := NewSessionManager(shell)

	// Create HTTP API handler.
	apiHandler := NewAPIHandler(token, manager)

	mux := http.NewServeMux()
	mux.HandleFunc("/api/create", apiHandler.HandleCreate)
	mux.HandleFunc("/api/input", apiHandler.HandleInput)
	mux.HandleFunc("/api/resize", apiHandler.HandleResize)
	mux.HandleFunc("/api/close", apiHandler.HandleClose)
	mux.HandleFunc("/api/poll", apiHandler.HandlePoll)
	mux.HandleFunc("/api/sessions", apiHandler.HandleSessions)
	mux.HandleFunc("/api/scrollback", apiHandler.HandleScrollback)
	mux.HandleFunc("/api/state", apiHandler.HandleState)
	mux.HandleFunc("/api/ws", apiHandler.HandleWebSocket)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	if staticDir != "" {
		mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir(staticDir))))
	}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	port := listener.Addr().(*net.TCPAddr).Port
	fmt.Printf("PID:%d\n", os.Getpid())
	fmt.Printf("PORT:%d\n", port)

	// Write startup info to a ready file if requested.
	// The file is written and closed immediately so the reader is never
	// blocked by a file lock (critical on Windows).
	if readyFile != "" {
		info := fmt.Sprintf("PID:%d\nPORT:%d\n", os.Getpid(), port)
		if err := os.WriteFile(readyFile, []byte(info), 0600); err != nil {
			log.Printf("warning: failed to write ready file: %v", err)
		}
	}

	// Monitor parent PID — exit if parent dies.
	parentPID := os.Getppid()
	go monitorParent(parentPID)

	// Idle timeout: counter-based instead of wall-clock timestamps.
	// Each tick increments a counter; any API request resets it to 0.
	// This is sleep/resume safe — the OS suspends the goroutine during
	// sleep, so no ticks fire and the counter doesn't jump on wake.
	go func() {
		const checkInterval = 5 * time.Second
		maxTicks := int64(idleTimeout / checkInterval)
		if maxTicks < 1 {
			maxTicks = 1
		}
		time.Sleep(checkInterval) // grace period on startup
		ticker := time.NewTicker(checkInterval)
		defer ticker.Stop()
		for range ticker.C {
			if apiHandler.IncrementIdle() >= maxTicks {
				if manager.Count() == 0 {
					log.Println("idle timeout reached with no active sessions, shutting down")
					os.Exit(0)
				}
				log.Println("idle timeout reached but sessions still active, resetting counter")
				apiHandler.ResetIdle()
			}
		}
	}()

	log.Fatal(http.Serve(listener, mux))
}

// monitorParent polls the parent PID and exits if it changes to 1 (init)
// which indicates the original parent has died.
func monitorParent(parentPID int) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		if os.Getppid() != parentPID {
			log.Println("parent process died, shutting down")
			os.Exit(0)
		}
	}
}
