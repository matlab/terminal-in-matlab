// Copyright 2026 The MathWorks, Inc.

package main

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"sync"
	"time"
)

// outputMessage represents a queued output message for polling.
type outputMessage struct {
	Type     string `json:"type"`              // "output" or "exited"
	ID       string `json:"id"`
	Data     string `json:"data,omitempty"`     // base64-encoded for output
	ExitCode *int   `json:"exitCode,omitempty"` // for exited
	Seq      int64  `json:"seq"`
}

// APIHandler handles HTTP API requests from MATLAB.
type APIHandler struct {
	token   string
	manager *SessionManager

	mu           sync.Mutex
	outputQueue  []outputMessage
	seq          int64
	lastActivity time.Time

	idleCounter int64 // incremented each idle-check tick; reset on API activity
}

// NewAPIHandler creates a new API handler.
func NewAPIHandler(token string, manager *SessionManager) *APIHandler {
	return &APIHandler{
		token:        token,
		manager:      manager,
		outputQueue:  make([]outputMessage, 0, 256),
		lastActivity: time.Now(),
	}
}

// LastActivity returns the time of the last API call.
func (h *APIHandler) LastActivity() time.Time {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.lastActivity
}

func (h *APIHandler) touch() {
	h.mu.Lock()
	h.lastActivity = time.Now()
	h.idleCounter = 0
	h.mu.Unlock()
}

// IncrementIdle bumps the idle counter and returns the new value.
func (h *APIHandler) IncrementIdle() int64 {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.idleCounter++
	return h.idleCounter
}

// ResetIdle resets the idle counter to zero.
func (h *APIHandler) ResetIdle() {
	h.mu.Lock()
	h.idleCounter = 0
	h.mu.Unlock()
}

func (h *APIHandler) enqueue(msg outputMessage) {
	h.mu.Lock()
	h.seq++
	msg.Seq = h.seq
	h.outputQueue = append(h.outputQueue, msg)
	// Keep only last 10000 messages to prevent unbounded growth.
	if len(h.outputQueue) > 10000 {
		h.outputQueue = h.outputQueue[len(h.outputQueue)-5000:]
	}
	h.mu.Unlock()

}

func (h *APIHandler) checkAuth(w http.ResponseWriter, r *http.Request) bool {
	auth := r.Header.Get("Authorization")
	if auth == "" || !validateToken(auth, h.token) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return false
	}
	return true
}

// HandleCreate creates a new PTY session.
func (h *APIHandler) HandleCreate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !h.checkAuth(w, r) {
		return
	}
	h.touch()

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var req struct {
		Shell string `json:"shell"`
		Cols  uint16 `json:"cols"`
		Rows  uint16 `json:"rows"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if req.Cols == 0 {
		req.Cols = 80
	}
	if req.Rows == 0 {
		req.Rows = 24
	}

	result, err := h.manager.Create(req.Shell, req.Cols, req.Rows,
		func(sessionID string, data []byte) {
			h.enqueue(outputMessage{
				Type: "output",
				ID:   sessionID,
				Data: base64.StdEncoding.EncodeToString(data),
			})
		},
		func(sessionID string, exitCode int) {
			h.enqueue(outputMessage{
				Type:     "exited",
				ID:       sessionID,
				ExitCode: &exitCode,
			})
		},
	)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"id": result.ID, "shell": result.Shell})
}

// HandleInput sends keystrokes to a session.
func (h *APIHandler) HandleInput(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !h.checkAuth(w, r) {
		return
	}
	h.touch()

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var req struct {
		ID   string `json:"id"`
		Data string `json:"data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	if err := h.manager.Write(req.ID, []byte(req.Data)); err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
}

// HandleResize changes a session's terminal size.
func (h *APIHandler) HandleResize(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !h.checkAuth(w, r) {
		return
	}
	h.touch()

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var req struct {
		ID   string `json:"id"`
		Cols uint16 `json:"cols"`
		Rows uint16 `json:"rows"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	if err := h.manager.Resize(req.ID, req.Cols, req.Rows); err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
}

// HandleClose terminates a session.
func (h *APIHandler) HandleClose(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !h.checkAuth(w, r) {
		return
	}
	h.touch()

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var req struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	if err := h.manager.Close(req.ID); err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
}

// HandlePoll returns queued output messages since a given sequence number.
func (h *APIHandler) HandlePoll(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !h.checkAuth(w, r) {
		return
	}
	h.touch()

	sinceStr := r.URL.Query().Get("since")
	var since int64
	if sinceStr != "" {
		json.Unmarshal([]byte(sinceStr), &since)
	}

	// Return immediately with any available messages (no long-poll).
	// MATLAB polls frequently via a timer, so blocking here would
	// prevent MATLAB's event loop from processing UI callbacks.
	messages := h.getMessagesSince(since)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"messages": messages})
}

// HandleSessions returns the IDs and count of active sessions.
func (h *APIHandler) HandleSessions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !h.checkAuth(w, r) {
		return
	}
	ids := h.manager.IDs()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"ids": ids, "count": len(ids)})
}

// HandleScrollback returns the scrollback buffer for a session.
// Prefers serialized xterm.js state if available (proper reflow on resize).
// Falls back to raw scrollback bytes for backward compatibility.
func (h *APIHandler) HandleScrollback(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !h.checkAuth(w, r) {
		return
	}
	id := r.URL.Query().Get("id")
	if id == "" {
		http.Error(w, "missing id parameter", http.StatusBadRequest)
		return
	}

	// Prefer serialized state — it reflows correctly on resize.
	if state := h.manager.SerializedState(id); state != "" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"serialized": state,
		})
		return
	}

	data := h.manager.Scrollback(id)
	if data == nil {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"data": base64.StdEncoding.EncodeToString(data),
	})
}

// HandleState stores or retrieves xterm.js serialized buffer state.
func (h *APIHandler) HandleState(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !h.checkAuth(w, r) {
		return
	}
	var req struct {
		ID    string `json:"id"`
		State string `json:"state"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if req.ID == "" || req.State == "" {
		http.Error(w, "missing id or state", http.StatusBadRequest)
		return
	}
	if err := h.manager.SetSerializedState(req.ID, req.State); err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (h *APIHandler) getMessagesSince(since int64) []outputMessage {
	h.mu.Lock()
	defer h.mu.Unlock()

	result := make([]outputMessage, 0)
	for _, msg := range h.outputQueue {
		if msg.Seq > since {
			result = append(result, msg)
		}
	}
	return result
}
