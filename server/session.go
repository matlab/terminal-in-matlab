// Copyright 2026 The MathWorks, Inc.

package main

import (
	"fmt"
	"io"
	"log"
	"sync"
)

const scrollbackCap = 128 * 1024 // 128 KB per session

// Session represents a single PTY session.
type Session struct {
	ID  string
	pty ptyProcess

	mu              sync.Mutex
	closed          bool
	scrollback      []byte // ring buffer of recent output
	serializedState string // xterm.js serialized buffer state (escape-code encoded)
}

// OutputCallback is called when there is output from a session.
type OutputCallback func(sessionID string, data []byte)

// ExitCallback is called when a session's process exits.
type ExitCallback func(sessionID string, exitCode int)

// SessionManager manages multiple PTY sessions.
type SessionManager struct {
	mu       sync.Mutex
	sessions map[string]*Session

	defaultShell string

	nextID int
}

// NewSessionManager creates a new session manager.
func NewSessionManager(defaultShell string) *SessionManager {
	return &SessionManager{
		sessions:     make(map[string]*Session),
		defaultShell: defaultShell,
	}
}

// Create starts a new PTY session. It calls onOutput for stdout data and
// onExit when the process terminates.
// CreateResult holds the result of creating a new session.
type CreateResult struct {
	ID    string
	Shell string
}

func (m *SessionManager) Create(shell string, cols, rows uint16, onOutput OutputCallback, onExit ExitCallback) (CreateResult, error) {
	if shell == "" {
		shell = m.defaultShell
	}

	m.mu.Lock()
	m.nextID++
	id := fmt.Sprintf("s%d", m.nextID)
	m.mu.Unlock()

	p, err := startPTY(shell, cols, rows)
	if err != nil {
		return CreateResult{}, fmt.Errorf("failed to start pty: %w", err)
	}

	sess := &Session{
		ID:         id,
		pty:        p,
		scrollback: make([]byte, 0, 4096),
	}

	m.mu.Lock()
	m.sessions[id] = sess
	m.mu.Unlock()

	// Wait goroutine: detects shell exit and unblocks Read().
	// On Windows, conpty.Read() never returns EOF when the shell
	// exits — it blocks forever. Calling Close() after Wait()
	// returns forces Read() to error out so the read goroutine
	// can proceed to cleanup. On Unix this is harmless.
	exitCodeCh := make(chan int, 1)
	go func() {
		exitCode, _ := p.Wait()
		exitCodeCh <- exitCode
		p.Close()
	}()

	// Read goroutine: reads PTY output and sends to callback.
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := p.Read(buf)
			if n > 0 {
				data := make([]byte, n)
				copy(data, buf[:n])
				sess.appendScrollback(data)
				onOutput(id, data)
			}
			if err != nil {
				if err != io.EOF {
					log.Printf("session %s read error: %v", id, err)
				}
				break
			}
		}

		exitCode := <-exitCodeCh

		m.mu.Lock()
		delete(m.sessions, id)
		m.mu.Unlock()

		onExit(id, exitCode)
	}()

	return CreateResult{ID: id, Shell: shell}, nil
}

// Write sends input data to a session's PTY.
func (m *SessionManager) Write(id string, data []byte) error {
	sess := m.get(id)
	if sess == nil {
		return fmt.Errorf("session %s not found", id)
	}
	_, err := sess.pty.Write(data)
	return err
}

// Resize changes the PTY window size.
func (m *SessionManager) Resize(id string, cols, rows uint16) error {
	sess := m.get(id)
	if sess == nil {
		return fmt.Errorf("session %s not found", id)
	}
	return sess.pty.Resize(cols, rows)
}

// Close terminates a session.
func (m *SessionManager) Close(id string) error {
	sess := m.get(id)
	if sess == nil {
		return fmt.Errorf("session %s not found", id)
	}

	sess.mu.Lock()
	defer sess.mu.Unlock()

	if sess.closed {
		return nil
	}
	sess.closed = true

	// Terminate the child process and close the PTY. The read goroutine
	// will see an error and exit, then Wait() handles final cleanup.
	sess.pty.Close()

	return nil
}

// Count returns the number of active sessions.
func (m *SessionManager) Count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.sessions)
}

// IDs returns the IDs of all active sessions.
func (m *SessionManager) IDs() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	ids := make([]string, 0, len(m.sessions))
	for id := range m.sessions {
		ids = append(ids, id)
	}
	return ids
}

// Scrollback returns the scrollback buffer for a session.
func (m *SessionManager) Scrollback(id string) []byte {
	sess := m.get(id)
	if sess == nil {
		return nil
	}
	sess.mu.Lock()
	defer sess.mu.Unlock()
	out := make([]byte, len(sess.scrollback))
	copy(out, sess.scrollback)
	return out
}

func (s *Session) appendScrollback(data []byte) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.scrollback = append(s.scrollback, data...)
	if len(s.scrollback) > scrollbackCap {
		// Keep only the tail.
		s.scrollback = s.scrollback[len(s.scrollback)-scrollbackCap:]
	}
}

// SerializedState returns the xterm.js serialized buffer state for a session.
func (m *SessionManager) SerializedState(id string) string {
	sess := m.get(id)
	if sess == nil {
		return ""
	}
	sess.mu.Lock()
	defer sess.mu.Unlock()
	return sess.serializedState
}

// SetSerializedState stores the xterm.js serialized buffer state for a session.
func (m *SessionManager) SetSerializedState(id, state string) error {
	sess := m.get(id)
	if sess == nil {
		return fmt.Errorf("session %s not found", id)
	}
	sess.mu.Lock()
	defer sess.mu.Unlock()
	sess.serializedState = state
	return nil
}

func (m *SessionManager) get(id string) *Session {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.sessions[id]
}
