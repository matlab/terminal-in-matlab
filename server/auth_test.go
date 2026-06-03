// Copyright 2026 The MathWorks, Inc.

package main

import "testing"

func TestValidateToken(t *testing.T) {
	tests := []struct {
		name     string
		provided string
		expected string
		want     bool
	}{
		{"exact match", "abc123", "abc123", true},
		{"wrong token", "wrong", "abc123", false},
		{"empty provided", "", "abc123", false},
		{"empty expected", "abc123", "", false},
		{"both empty", "", "", true},
		{"substring", "abc", "abc123", false},
		{"superstring", "abc1234", "abc123", false},
		{"case sensitive", "ABC123", "abc123", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := validateToken(tt.provided, tt.expected); got != tt.want {
				t.Errorf("validateToken(%q, %q) = %v, want %v", tt.provided, tt.expected, got, tt.want)
			}
		})
	}
}
