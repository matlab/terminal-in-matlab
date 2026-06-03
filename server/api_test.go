// Copyright 2026 The MathWorks, Inc.

package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const testToken = "test-token-abc123"

func newTestHandler() *APIHandler {
	manager := NewSessionManager(defaultShell())
	return NewAPIHandler(testToken, manager)
}

func authHeader(token string) http.Header {
	h := http.Header{}
	h.Set("Authorization", token)
	return h
}

// --- Auth tests ---

func TestAuth_Unauthorized(t *testing.T) {
	h := newTestHandler()
	endpoints := []struct {
		method, path string
	}{
		{"POST", "/api/create"},
		{"POST", "/api/input"},
		{"POST", "/api/resize"},
		{"POST", "/api/close"},
		{"GET", "/api/poll"},
		{"GET", "/api/sessions"},
		{"GET", "/api/scrollback?id=s1"},
	}

	handlers := map[string]http.HandlerFunc{
		"/api/create":    h.HandleCreate,
		"/api/input":     h.HandleInput,
		"/api/resize":    h.HandleResize,
		"/api/close":     h.HandleClose,
		"/api/poll":      h.HandlePoll,
		"/api/sessions":  h.HandleSessions,
		"/api/scrollback": h.HandleScrollback,
	}

	for _, ep := range endpoints {
		t.Run(ep.method+" "+ep.path+" no token", func(t *testing.T) {
			path := ep.path
			if idx := strings.Index(path, "?"); idx != -1 {
				path = path[:idx]
			}
			req := httptest.NewRequest(ep.method, ep.path, nil)
			w := httptest.NewRecorder()
			handlers[path](w, req)
			if w.Code != http.StatusUnauthorized {
				t.Errorf("got %d, want 401", w.Code)
			}
		})

		t.Run(ep.method+" "+ep.path+" wrong token", func(t *testing.T) {
			path := ep.path
			if idx := strings.Index(path, "?"); idx != -1 {
				path = path[:idx]
			}
			req := httptest.NewRequest(ep.method, ep.path, nil)
			req.Header = authHeader("wrong-token")
			w := httptest.NewRecorder()
			handlers[path](w, req)
			if w.Code != http.StatusUnauthorized {
				t.Errorf("got %d, want 401", w.Code)
			}
		})
	}
}

func TestAuth_WrongMethod(t *testing.T) {
	h := newTestHandler()

	tests := []struct {
		name, method, path string
		handler            http.HandlerFunc
	}{
		{"GET on create", "GET", "/api/create", h.HandleCreate},
		{"GET on input", "GET", "/api/input", h.HandleInput},
		{"GET on resize", "GET", "/api/resize", h.HandleResize},
		{"GET on close", "GET", "/api/close", h.HandleClose},
		{"POST on poll", "POST", "/api/poll", h.HandlePoll},
		{"POST on sessions", "POST", "/api/sessions", h.HandleSessions},
		{"POST on scrollback", "POST", "/api/scrollback", h.HandleScrollback},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, tt.path, nil)
			req.Header = authHeader(testToken)
			w := httptest.NewRecorder()
			tt.handler(w, req)
			if w.Code != http.StatusMethodNotAllowed {
				t.Errorf("got %d, want 405", w.Code)
			}
		})
	}
}

// --- HandleCreate tests ---

func TestCreate_InvalidJSON(t *testing.T) {
	h := newTestHandler()

	bodies := []struct {
		name string
		body string
	}{
		{"garbage", "{{{"},
		{"empty", ""},
		{"plain text", "hello"},
	}

	for _, tt := range bodies {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest("POST", "/api/create", strings.NewReader(tt.body))
			req.Header = authHeader(testToken)
			w := httptest.NewRecorder()
			h.HandleCreate(w, req)
			if w.Code != http.StatusBadRequest {
				t.Errorf("body=%q: got %d, want 400", tt.body, w.Code)
			}
		})
	}
}

func TestCreate_ValidJSON(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest("POST", "/api/create", strings.NewReader(`{"cols":80,"rows":24}`))
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandleCreate(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("got %d, want 200", w.Code)
	}

	var resp map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("invalid JSON response: %v", err)
	}
	if resp["id"] == "" {
		t.Error("response missing 'id'")
	}
	if resp["shell"] == "" {
		t.Error("response missing 'shell'")
	}

	// Clean up
	h.manager.Close(resp["id"])
}

func TestCreate_DefaultDimensions(t *testing.T) {
	h := newTestHandler()

	// Cols/rows omitted — should default to 80x24 and succeed.
	req := httptest.NewRequest("POST", "/api/create", strings.NewReader(`{"shell":""}`))
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandleCreate(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("got %d, want 200", w.Code)
	}

	var resp map[string]string
	json.Unmarshal(w.Body.Bytes(), &resp)
	h.manager.Close(resp["id"])
}

func TestCreate_OversizedBody(t *testing.T) {
	h := newTestHandler()

	// 2 MB body — exceeds the 1 MB MaxBytesReader limit.
	bigBody := strings.Repeat("A", 2*1024*1024)
	req := httptest.NewRequest("POST", "/api/create", strings.NewReader(bigBody))
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandleCreate(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}

	// Verify no session was created.
	if count := h.manager.Count(); count != 0 {
		t.Errorf("session count = %d, want 0", count)
	}
}

// --- HandlePoll tests ---

func TestPoll_EmptyMessages(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest("GET", "/api/poll?since=0", nil)
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandlePoll(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("got %d, want 200", w.Code)
	}

	// Must be [] not null.
	body := strings.TrimSpace(w.Body.String())
	var resp map[string]json.RawMessage
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if string(resp["messages"]) == "null" {
		t.Error("messages is null, want []")
	}
	if string(resp["messages"]) != "[]" {
		t.Errorf("messages = %s, want []", resp["messages"])
	}
}

func TestPoll_WithMessages(t *testing.T) {
	h := newTestHandler()

	h.enqueue(outputMessage{Type: "output", ID: "s1", Data: "aGVsbG8="})
	h.enqueue(outputMessage{Type: "output", ID: "s1", Data: "d29ybGQ="})

	req := httptest.NewRequest("GET", "/api/poll?since=0", nil)
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandlePoll(w, req)

	var resp struct {
		Messages []outputMessage `json:"messages"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)

	if len(resp.Messages) != 2 {
		t.Fatalf("got %d messages, want 2", len(resp.Messages))
	}
	if resp.Messages[0].Seq != 1 || resp.Messages[1].Seq != 2 {
		t.Errorf("unexpected sequence numbers: %d, %d", resp.Messages[0].Seq, resp.Messages[1].Seq)
	}
}

func TestPoll_SinceFilters(t *testing.T) {
	h := newTestHandler()

	h.enqueue(outputMessage{Type: "output", ID: "s1", Data: "Zmlyc3Q="})
	h.enqueue(outputMessage{Type: "output", ID: "s1", Data: "c2Vjb25k"})
	h.enqueue(outputMessage{Type: "output", ID: "s1", Data: "dGhpcmQ="})

	req := httptest.NewRequest("GET", "/api/poll?since=2", nil)
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandlePoll(w, req)

	var resp struct {
		Messages []outputMessage `json:"messages"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)

	if len(resp.Messages) != 1 {
		t.Fatalf("got %d messages, want 1", len(resp.Messages))
	}
	if resp.Messages[0].Seq != 3 {
		t.Errorf("got seq %d, want 3", resp.Messages[0].Seq)
	}
}

// --- HandleSessions tests ---

func TestSessions_Empty(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest("GET", "/api/sessions", nil)
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandleSessions(w, req)

	var resp struct {
		Count int      `json:"count"`
		IDs   []string `json:"ids"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)

	if resp.Count != 0 {
		t.Errorf("count = %d, want 0", resp.Count)
	}
}

// --- HandleClose tests ---

func TestClose_NonexistentSession(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest("POST", "/api/close", strings.NewReader(`{"id":"bogus"}`))
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandleClose(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("got %d, want 404", w.Code)
	}
}

// --- HandleInput tests ---

func TestInput_NonexistentSession(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest("POST", "/api/input", strings.NewReader(`{"id":"bogus","data":"hello"}`))
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandleInput(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("got %d, want 404", w.Code)
	}
}

func TestInput_InvalidJSON(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest("POST", "/api/input", strings.NewReader("{{{"))
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandleInput(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

// --- HandleScrollback tests ---

func TestScrollback_MissingID(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest("GET", "/api/scrollback", nil)
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandleScrollback(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestScrollback_NonexistentSession(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest("GET", "/api/scrollback?id=bogus", nil)
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandleScrollback(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("got %d, want 404", w.Code)
	}
}

// --- Idle counter tests ---

func TestIncrementIdle_Increments(t *testing.T) {
	h := newTestHandler()

	if v := h.IncrementIdle(); v != 1 {
		t.Errorf("first increment = %d, want 1", v)
	}
	if v := h.IncrementIdle(); v != 2 {
		t.Errorf("second increment = %d, want 2", v)
	}
}

func TestResetIdle_ResetsCounter(t *testing.T) {
	h := newTestHandler()

	h.IncrementIdle()
	h.IncrementIdle()
	h.IncrementIdle()
	h.ResetIdle()

	if v := h.IncrementIdle(); v != 1 {
		t.Errorf("after reset, increment = %d, want 1", v)
	}
}

func TestTouch_ResetsIdleCounter(t *testing.T) {
	h := newTestHandler()

	h.IncrementIdle()
	h.IncrementIdle()

	// An API call (poll) should reset the counter via touch().
	req := httptest.NewRequest("GET", "/api/poll?since=0", nil)
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandlePoll(w, req)

	if v := h.IncrementIdle(); v != 1 {
		t.Errorf("after touch, increment = %d, want 1", v)
	}
}

// --- LastActivity tests ---

func TestLastActivity_UpdatedOnRequest(t *testing.T) {
	h := newTestHandler()

	before := h.LastActivity()
	time.Sleep(10 * time.Millisecond)

	req := httptest.NewRequest("GET", "/api/poll?since=0", nil)
	req.Header = authHeader(testToken)
	w := httptest.NewRecorder()
	h.HandlePoll(w, req)

	after := h.LastActivity()
	if !after.After(before) {
		t.Error("LastActivity was not updated after request")
	}
}
