// Copyright 2026 The MathWorks, Inc.

package main

import (
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		// Allow all origins — auth is token-based, not origin-based.
		return true
	},
}

// wsMessage is a JSON control message sent over text frames.
type wsMessage struct {
	Type  string `json:"type"`
	ID    string `json:"id,omitempty"`
	Cols  uint16 `json:"cols,omitempty"`
	Rows  uint16 `json:"rows,omitempty"`
	Data  string `json:"data,omitempty"` // base64-encoded for output/scrollback
	Meta  string `json:"meta,omitempty"` // "serialized" when Data is xterm.js state
	Shell string `json:"shell,omitempty"`
}

// HandleWebSocket upgrades to a WebSocket connection and multiplexes
// all PTY sessions over it. The browser can create/close/resize sessions
// and send input, all through a single persistent connection.
func (h *APIHandler) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Auth via query parameter (WebSocket can't set headers from browser).
	token := r.URL.Query().Get("token")
	if token == "" || !validateToken(token, h.token) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	h.touch()

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("websocket upgrade failed: %v", err)
		return
	}

	ws := &wsConn{
		conn:    conn,
		handler: h,
	}
	ws.run()
}

// wsConn manages a single WebSocket connection with multiplexed sessions.
type wsConn struct {
	conn    *websocket.Conn
	handler *APIHandler

	writeMu sync.Mutex // serializes writes to the WS connection
}

// sendJSON sends a JSON text frame to the browser.
func (ws *wsConn) sendJSON(msg wsMessage) {
	ws.writeMu.Lock()
	defer ws.writeMu.Unlock()
	ws.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	ws.conn.WriteJSON(msg)
}

func (ws *wsConn) run() {
	defer ws.conn.Close()

	// Keep the server alive while a WebSocket client is connected.
	done := make(chan struct{})
	defer close(done)
	go func() {
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				return
			case <-ticker.C:
				ws.handler.touch()
				ws.writeMu.Lock()
				ws.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
				ws.conn.WriteMessage(websocket.PingMessage, nil)
				ws.writeMu.Unlock()
			}
		}
	}()

	ws.conn.SetPongHandler(func(string) error {
		ws.handler.touch()
		return nil
	})

	for {
		_, raw, err := ws.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("websocket read error: %v", err)
			}
			return
		}
		ws.handler.touch()

		var msg struct {
			Type  string `json:"type"`
			ID    string `json:"id"`
			Data  string `json:"data"`
			Cols  uint16 `json:"cols"`
			Rows  uint16 `json:"rows"`
			Shell string `json:"shell"`
		}
		if err := json.Unmarshal(raw, &msg); err != nil {
			log.Printf("websocket: invalid message: %v", err)
			continue
		}

		switch msg.Type {
		case "create":
			ws.handleCreate(msg.Shell)
		case "input":
			ws.handleInput(msg.ID, msg.Data)
		case "resize":
			ws.handleResize(msg.ID, msg.Cols, msg.Rows)
		case "close":
			ws.handleClose(msg.ID)
		case "sessions":
			ws.handleSessions()
		case "state":
			ws.handler.manager.SetSerializedState(msg.ID, msg.Data)
		}
	}
}

func (ws *wsConn) handleCreate(shell string) {
	result, err := ws.handler.manager.Create(shell, 80, 24,
		func(sessionID string, data []byte) {
			ws.sendJSON(wsMessage{
				Type: "output",
				ID:   sessionID,
				Data: base64.StdEncoding.EncodeToString(data),
			})
		},
		func(sessionID string, exitCode int) {
			ws.sendJSON(wsMessage{
				Type: "exited",
				ID:   sessionID,
			})
		},
	)
	if err != nil {
		log.Printf("websocket: create failed: %v", err)
		ws.sendJSON(wsMessage{Type: "error", Data: err.Error()})
		return
	}

	ws.sendJSON(wsMessage{Type: "created", ID: result.ID})
}

func (ws *wsConn) handleInput(id, data string) {
	if err := ws.handler.manager.Write(id, []byte(data)); err != nil {
		log.Printf("websocket: write to %s failed: %v", id, err)
	}
}

func (ws *wsConn) handleResize(id string, cols, rows uint16) {
	if cols == 0 || rows == 0 {
		return
	}
	if err := ws.handler.manager.Resize(id, cols, rows); err != nil {
		log.Printf("websocket: resize %s failed: %v", id, err)
	}
}

func (ws *wsConn) handleClose(id string) {
	if err := ws.handler.manager.Close(id); err != nil {
		log.Printf("websocket: close %s failed: %v", id, err)
	}
}

func (ws *wsConn) handleSessions() {
	ids := ws.handler.manager.IDs()
	for _, id := range ids {
		// Prefer serialized xterm.js state — reflows correctly on resize.
		if state := ws.handler.manager.SerializedState(id); state != "" {
			ws.sendJSON(wsMessage{
				Type: "session",
				ID:   id,
				Data: state,
				Meta: "serialized",
			})
		} else {
			data := ws.handler.manager.Scrollback(id)
			scrollback := ""
			if data != nil {
				scrollback = base64.StdEncoding.EncodeToString(data)
			}
			ws.sendJSON(wsMessage{
				Type: "session",
				ID:   id,
				Data: scrollback,
			})
		}
	}
	ws.sendJSON(wsMessage{Type: "sessions_done"})
}
