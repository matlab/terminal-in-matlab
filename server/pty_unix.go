// Copyright 2026 The MathWorks, Inc.

//go:build !windows

package main

import (
	"os"
	"os/exec"
	"syscall"

	"github.com/creack/pty"
)

type unixPTY struct {
	cmd  *exec.Cmd
	ptmx *os.File
}

func startPTY(shell string, cols, rows uint16) (ptyProcess, error) {
	cmd := exec.Command(shell)
	ptmx, err := pty.StartWithSize(cmd, &pty.Winsize{
		Cols: cols,
		Rows: rows,
	})
	if err != nil {
		return nil, err
	}
	return &unixPTY{cmd: cmd, ptmx: ptmx}, nil
}

func (p *unixPTY) Read(b []byte) (int, error)  { return p.ptmx.Read(b) }
func (p *unixPTY) Write(b []byte) (int, error) { return p.ptmx.Write(b) }
func (p *unixPTY) Close() error {
	if p.cmd.Process != nil {
		// Send SIGHUP to the entire process group (negative PID).
		// Interactive bash ignores SIGTERM, but handles SIGHUP by
		// forwarding it to all jobs before exiting. The child runs
		// in its own session (setsid), so its PID equals the PGID.
		syscall.Kill(-p.cmd.Process.Pid, syscall.SIGHUP)
	}
	return p.ptmx.Close()
}

func (p *unixPTY) Resize(cols, rows uint16) error {
	return pty.Setsize(p.ptmx, &pty.Winsize{Cols: cols, Rows: rows})
}

func (p *unixPTY) Wait() (int, error) {
	err := p.cmd.Wait()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			if status, ok := exitErr.Sys().(syscall.WaitStatus); ok {
				return status.ExitStatus(), nil
			}
		}
		return 1, err
	}
	return 0, nil
}
