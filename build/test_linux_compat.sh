#!/bin/bash
# Copyright 2026 The MathWorks, Inc.
#
# Regression test for the RHEL 8 / glibc compatibility fix.
#
# The Linux server binary must NOT dynamically link a newer glibc than older
# supported distributions ship. When built with the default CGO_ENABLED=1 on a
# modern build host, Go links the host glibc and the binary fails to load on
# e.g. RHEL 8.10 (glibc 2.28) with:
#     version `GLIBC_2.34' not found (required by matlab-terminal-server)
#
# Building with CGO_ENABLED=0 produces a statically linked, pure-Go binary with
# no libc dependency. This script builds the linux/amd64 server and verifies it
# runs on an old-glibc container that mirrors RHEL 8.
#
# Usage:   ./build/test_linux_compat.sh    (run from the repo root or anywhere)
# Requires: go, and a container runtime (docker or podman).
# Exit 0 on pass, non-zero on failure. Skips (exit 0) if no runtime is found.

set -euo pipefail

# Resolve repo layout relative to this script so it runs from any directory.
scriptDir="$(cd "$(dirname "$0")" && pwd)"
serverDir="$(cd "$scriptDir/../server" && pwd)"

# RHEL 8.10 ships glibc 2.28; UBI 8 is Red Hat's official matching base image.
IMAGE="${COMPAT_IMAGE:-redhat/ubi8:latest}"
BIN="$(mktemp -d)/matlab-terminal-server"

# Pick a container runtime.
if command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
elif command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
else
  echo "SKIP: no docker/podman runtime found; cannot run glibc compat test."
  exit 0
fi

echo "== Building linux/amd64 server with CGO_ENABLED=0 =="
(cd "$serverDir" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -ldflags="-s -w" -o "$BIN" .)

echo "== Static-linking assertions =="
# The binary must not require any versioned GLIBC symbols.
if command -v objdump >/dev/null 2>&1; then
  if objdump -T "$BIN" 2>/dev/null | grep -q 'GLIBC_'; then
    echo "FAIL: binary requires versioned GLIBC symbols (expected none):"
    objdump -T "$BIN" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -uV
    exit 1
  fi
  echo "  ok: no GLIBC_* symbol requirements"
fi

echo "== Runtime check on $IMAGE (glibc $($RUNTIME run --rm "$IMAGE" ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)) =="
# The server prints "PORT:<n>" once it is listening, then blocks serving.
# We give it a short window and assert that line appears (i.e. it loaded and
# started) rather than dying with a loader error.
OUT="$($RUNTIME run --rm -v "$BIN":/matlab-terminal-server:ro "$IMAGE" \
  timeout 5 /matlab-terminal-server --token=compat-test 2>&1 || true)"

echo "$OUT" | sed 's/^/  server> /'

if echo "$OUT" | grep -q 'GLIBC_'; then
  echo "FAIL: binary failed to load due to missing GLIBC symbols."
  exit 1
fi
if ! echo "$OUT" | grep -q '^PORT:[0-9]'; then
  echo "FAIL: server did not report a port on $IMAGE."
  exit 1
fi

echo "PASS: server starts on $IMAGE without glibc errors."
