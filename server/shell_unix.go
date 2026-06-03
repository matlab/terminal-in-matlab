// Copyright 2026 The MathWorks, Inc.

//go:build !windows

package main

import "os"

func defaultShell() string {
	if s := os.Getenv("SHELL"); s != "" {
		return s
	}
	return "/bin/sh"
}
