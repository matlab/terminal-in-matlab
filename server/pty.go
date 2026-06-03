// Copyright 2026 The MathWorks, Inc.

package main

// ptyProcess abstracts a PTY-attached process across platforms.
// On Unix, this wraps creack/pty. On Windows, this wraps ConPTY.
type ptyProcess interface {
	Read(p []byte) (n int, err error)
	Write(p []byte) (n int, err error)
	Resize(cols, rows uint16) error
	Close() error // Terminate the child process and close the PTY
	Wait() (exitCode int, err error)
}
