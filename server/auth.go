// Copyright 2026 The MathWorks, Inc.

package main

import "crypto/subtle"

// validateToken performs a constant-time comparison of the provided token
// against the expected token to prevent timing attacks.
func validateToken(provided, expected string) bool {
	return subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) == 1
}
