// Copyright 2026 The MathWorks, Inc.

//go:build windows

package main

import "os"

func defaultShell() string {
	if s := os.Getenv("COMSPEC"); s != "" {
		return s
	}
	return "cmd.exe"
}
