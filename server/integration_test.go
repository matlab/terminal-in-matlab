// Copyright 2026 The MathWorks, Inc.

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"testing"
	"time"
)

const integrationToken = "integration-test-token"

// startTestServer creates a real HTTP server with all API routes.
func startTestServer(t *testing.T) (*httptest.Server, *APIHandler) {
	t.Helper()
	manager := NewSessionManager(defaultShell())
	handler := NewAPIHandler(integrationToken, manager)

	mux := http.NewServeMux()
	mux.HandleFunc("/api/create", handler.HandleCreate)
	mux.HandleFunc("/api/input", handler.HandleInput)
	mux.HandleFunc("/api/resize", handler.HandleResize)
	mux.HandleFunc("/api/close", handler.HandleClose)
	mux.HandleFunc("/api/poll", handler.HandlePoll)
	mux.HandleFunc("/api/sessions", handler.HandleSessions)
	mux.HandleFunc("/api/scrollback", handler.HandleScrollback)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})

	return httptest.NewServer(mux), handler
}

// apiCall makes an authenticated HTTP request and returns status code and
// parsed JSON response.
func apiCall(t *testing.T, base, method, path, body string) (int, map[string]interface{}) {
	t.Helper()
	var bodyReader io.Reader
	if body != "" {
		bodyReader = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, base+path, bodyReader)
	if err != nil {
		t.Fatalf("create request: %v", err)
	}
	req.Header.Set("Authorization", integrationToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	var result map[string]interface{}
	json.Unmarshal(b, &result)
	return resp.StatusCode, result
}

// sessionCount returns the current session count from /api/sessions.
func sessionCount(t *testing.T, base string) int {
	t.Helper()
	_, resp := apiCall(t, base, "GET", "/api/sessions", "")
	return int(resp["count"].(float64))
}

func TestIntegration_CreateAndList(t *testing.T) {
	srv, _ := startTestServer(t)
	defer srv.Close()
	base := srv.URL

	// Health check.
	code, _ := apiCall(t, base, "GET", "/health", "")
	if code != 200 {
		t.Fatalf("health: got %d", code)
	}

	// No sessions initially.
	if n := sessionCount(t, base); n != 0 {
		t.Fatalf("initial sessions = %d, want 0", n)
	}

	// Create session 1.
	code, resp := apiCall(t, base, "POST", "/api/create", `{"cols":80,"rows":24}`)
	if code != 200 {
		t.Fatalf("create s1: got %d", code)
	}
	s1 := resp["id"].(string)
	if s1 == "" {
		t.Fatal("create returned empty id")
	}
	if resp["shell"] == nil || resp["shell"] == "" {
		t.Error("create missing shell in response")
	}

	// Create session 2 with different dimensions.
	code, resp = apiCall(t, base, "POST", "/api/create", `{"cols":120,"rows":40}`)
	if code != 200 {
		t.Fatalf("create s2: got %d", code)
	}
	s2 := resp["id"].(string)

	// Verify 2 sessions.
	if n := sessionCount(t, base); n != 2 {
		t.Errorf("session count = %d, want 2", n)
	}

	// IDs should differ.
	if s1 == s2 {
		t.Error("two sessions got the same ID")
	}

	// Clean up.
	apiCall(t, base, "POST", "/api/close", fmt.Sprintf(`{"id":"%s"}`, s1))
	apiCall(t, base, "POST", "/api/close", fmt.Sprintf(`{"id":"%s"}`, s2))
}

func TestIntegration_InputAndPoll(t *testing.T) {
	srv, _ := startTestServer(t)
	defer srv.Close()
	base := srv.URL

	// Create a session.
	_, resp := apiCall(t, base, "POST", "/api/create", `{"cols":80,"rows":24}`)
	id := resp["id"].(string)

	// Send input.
	code, _ := apiCall(t, base, "POST", "/api/input",
		fmt.Sprintf(`{"id":"%s","data":"echo hello\n"}`, id))
	if code != 200 {
		t.Fatalf("input: got %d", code)
	}

	// Wait for output.
	time.Sleep(500 * time.Millisecond)

	// Poll should return output messages.
	code, resp = apiCall(t, base, "GET", "/api/poll?since=0", "")
	if code != 200 {
		t.Fatalf("poll: got %d", code)
	}
	messages, ok := resp["messages"].([]interface{})
	if !ok || len(messages) == 0 {
		t.Error("poll returned no messages after input")
	}

	// Clean up.
	apiCall(t, base, "POST", "/api/close", fmt.Sprintf(`{"id":"%s"}`, id))
}

func TestIntegration_Resize(t *testing.T) {
	srv, _ := startTestServer(t)
	defer srv.Close()
	base := srv.URL

	_, resp := apiCall(t, base, "POST", "/api/create", `{"cols":80,"rows":24}`)
	id := resp["id"].(string)

	code, _ := apiCall(t, base, "POST", "/api/resize",
		fmt.Sprintf(`{"id":"%s","cols":100,"rows":30}`, id))
	if code != 200 {
		t.Fatalf("resize: got %d", code)
	}

	// Clean up.
	apiCall(t, base, "POST", "/api/close", fmt.Sprintf(`{"id":"%s"}`, id))
}

func TestIntegration_Scrollback(t *testing.T) {
	srv, _ := startTestServer(t)
	defer srv.Close()
	base := srv.URL

	_, resp := apiCall(t, base, "POST", "/api/create", `{"cols":80,"rows":24}`)
	id := resp["id"].(string)

	// Send some input to generate scrollback.
	apiCall(t, base, "POST", "/api/input",
		fmt.Sprintf(`{"id":"%s","data":"echo scrollback-test\n"}`, id))
	time.Sleep(500 * time.Millisecond)

	code, resp := apiCall(t, base, "GET", fmt.Sprintf("/api/scrollback?id=%s", id), "")
	if code != 200 {
		t.Fatalf("scrollback: got %d", code)
	}
	if resp["data"] == nil {
		t.Error("scrollback response missing 'data' field")
	}

	// Clean up.
	apiCall(t, base, "POST", "/api/close", fmt.Sprintf(`{"id":"%s"}`, id))
}

func TestIntegration_Close(t *testing.T) {
	srv, _ := startTestServer(t)
	defer srv.Close()
	base := srv.URL

	_, resp := apiCall(t, base, "POST", "/api/create", `{"cols":80,"rows":24}`)
	id := resp["id"].(string)

	// Close should succeed.
	code, _ := apiCall(t, base, "POST", "/api/close", fmt.Sprintf(`{"id":"%s"}`, id))
	if code != 200 {
		t.Fatalf("close: got %d", code)
	}

	// Closing again should be idempotent (200) while session is
	// still in the map, or 404 once async cleanup removes it.
	code, _ = apiCall(t, base, "POST", "/api/close", fmt.Sprintf(`{"id":"%s"}`, id))
	if code != 200 && code != http.StatusNotFound {
		t.Errorf("double close: got %d, want 200 or 404", code)
	}

	// Bogus ID should return 404.
	code, _ = apiCall(t, base, "POST", "/api/close", `{"id":"nonexistent"}`)
	if code != http.StatusNotFound {
		t.Errorf("close bogus: got %d, want 404", code)
	}
}

func TestIntegration_ShellExit(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("ConPTY Read() does not unblock reliably on shell exit in CI")
	}

	srv, _ := startTestServer(t)
	defer srv.Close()
	base := srv.URL

	// Create a session.
	_, resp := apiCall(t, base, "POST", "/api/create", `{"cols":80,"rows":24}`)
	id := resp["id"].(string)

	// Send 'exit' command.
	apiCall(t, base, "POST", "/api/input",
		fmt.Sprintf(`{"id":"%s","data":"exit\n"}`, id))

	// Wait for shell to exit and read goroutine to clean up.
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if sessionCount(t, base) == 0 {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}

	// Poll should contain an "exited" message.
	_, resp = apiCall(t, base, "GET", "/api/poll?since=0", "")
	messages := resp["messages"].([]interface{})
	foundExited := false
	for _, m := range messages {
		msg := m.(map[string]interface{})
		if msg["type"] == "exited" && msg["id"] == id {
			foundExited = true
			break
		}
	}
	if !foundExited {
		t.Error("no 'exited' message found after shell exit")
	}
}

func TestIntegration_CloseOneSurvivesOther(t *testing.T) {
	// ConPTY can occasionally hang during close in CI (see #36).
	timer := time.AfterFunc(30*time.Second, func() {
		panic("TestIntegration_CloseOneSurvivesOther timed out after 30s")
	})
	defer timer.Stop()

	srv, _ := startTestServer(t)
	defer srv.Close()
	base := srv.URL

	// Create two sessions.
	_, r1 := apiCall(t, base, "POST", "/api/create", `{"cols":80,"rows":24}`)
	s1 := r1["id"].(string)
	_, r2 := apiCall(t, base, "POST", "/api/create", `{"cols":80,"rows":24}`)
	s2 := r2["id"].(string)

	if sessionCount(t, base) != 2 {
		t.Fatal("expected 2 sessions before close")
	}

	// Close s1.
	code, _ := apiCall(t, base, "POST", "/api/close", fmt.Sprintf(`{"id":"%s"}`, s1))
	if code != 200 {
		t.Fatalf("close s1: got %d", code)
	}

	// Send input to s2 — should still work.
	code, _ = apiCall(t, base, "POST", "/api/input",
		fmt.Sprintf(`{"id":"%s","data":"echo alive\n"}`, s2))
	if code != 200 {
		t.Errorf("input to s2 after closing s1: got %d, want 200", code)
	}

	// Clean up.
	apiCall(t, base, "POST", "/api/close", fmt.Sprintf(`{"id":"%s"}`, s2))
}
