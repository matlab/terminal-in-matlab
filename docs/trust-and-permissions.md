# Security Model

Terminal launches a local Go server that manages PTY (pseudo-terminal) sessions. The terminal runs with the same permissions as the MATLAB process — there is no privilege escalation.

## Authentication

All HTTP communication between MATLAB and the Go server is protected by a per-session authentication token:

- MATLAB generates a random 32-character hex token each time a terminal is created
- The token is passed to the Go server via environment variable (not visible in `ps` or `/proc/*/cmdline`)
- Every HTTP request includes the token in the `Authorization` header
- The server rejects requests without a valid token using constant-time comparison

## Network Binding

The Go server binds exclusively to `127.0.0.1` (loopback) on a randomly assigned port. It is not accessible from the network.

## Process Lifecycle

- The server is started by MATLAB and killed when the terminal is closed or MATLAB exits
- An idle timeout (default 30 seconds) causes the server to self-terminate when no client activity is detected
- The server monitors its parent PID and exits if the parent process dies
- If the server process dies unexpectedly (e.g., after system sleep), MATLAB automatically detects the failure and relaunches it

---

## Supply Chain Security

Every release artifact is built in GitHub Actions and published with cryptographic provenance so you can verify that binaries came from this repository's CI pipeline, not from a compromised machine or tampered release.

### What Gets Published

Each [GitHub Release](https://github.com/matlab/terminal-in-matlab/releases) includes:

| Artifact                           | Description                                                     |
| ---------------------------------- | --------------------------------------------------------------- |
| `Terminal.mltbx`                   | MATLAB toolbox package (contains all platform binaries)         |
| `matlab-terminal-server-glnxa64`   | Linux x86_64 server binary                                      |
| `matlab-terminal-server-maci64`    | macOS Intel server binary                                       |
| `matlab-terminal-server-maca64`    | macOS Apple Silicon server binary                               |
| `matlab-terminal-server-win64.exe` | Windows x86_64 server binary                                    |
| `checksums.txt`                    | SHA-256 checksums for all artifacts                             |
| `multiple.intoto.jsonl`            | [SLSA v1.0](https://slsa.dev/) provenance attestation (Level 3) |

### Verifying From MATLAB

The simplest way to verify your installation:

```matlab
terminal.verify()
```

This automatically:

1. Computes the SHA-256 hash of the installed server binary
2. Fetches `checksums.txt` from the matching GitHub release
3. Compares the hashes
4. If [`slsa-verifier`](https://github.com/slsa-framework/slsa-verifier) is on your system PATH, also runs full SLSA provenance verification

### Manual Verification (SHA-256 Checksums)

Download `checksums.txt` from the release and verify locally:

```bash
# Download the release assets
gh release download v0.10.1 -R matlab/terminal-in-matlab

# Verify checksums
sha256sum -c checksums.txt
```

This confirms the files you downloaded match what the CI pipeline produced. It protects against download corruption and third-party tampering with release assets.

### Manual Verification (SLSA Provenance)

For stronger guarantees, verify the [SLSA provenance](https://slsa.dev/) attestation using [`slsa-verifier`](https://github.com/slsa-framework/slsa-verifier):

```bash
# Install slsa-verifier (one-time)
go install github.com/slsa-framework/slsa-verifier/v2/cli/slsa-verifier@latest

# Verify the .mltbx
slsa-verifier verify-artifact \
  --provenance-path multiple.intoto.jsonl \
  --source-uri github.com/matlab/terminal-in-matlab \
  --source-tag v0.10.1 \
  Terminal.mltbx

# Verify a specific platform binary
slsa-verifier verify-artifact \
  --provenance-path multiple.intoto.jsonl \
  --source-uri github.com/matlab/terminal-in-matlab \
  --source-tag v0.10.1 \
  matlab-terminal-server-glnxa64
```

A successful verification proves:

- The artifact was built by the `release.yml` workflow in `matlab/terminal-in-matlab`
- It was built from the exact tagged commit (not a modified source)
- The build ran on a GitHub-hosted runner in an isolated environment that the repository owner cannot tamper with
- The attestation is signed via [Sigstore](https://www.sigstore.dev/) and logged in a public [Rekor](https://docs.sigstore.dev/logging/overview/) transparency log

### What SLSA L3 Protects Against

| Threat                                | Checksums                                             | SLSA L3                                                                                        |
| ------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Download corruption                   | Yes                                                   | Yes                                                                                            |
| Tampered release assets (third party) | Yes                                                   | Yes                                                                                            |
| Compromised maintainer credentials    | No — attacker can replace binary + checksums together | Yes — provenance is generated by GitHub-controlled infrastructure the maintainer cannot modify |
| Modified build pipeline               | No                                                    | Yes — the reusable workflow is pinned and isolated                                             |
| Forged provenance                     | N/A                                                   | Protected by Sigstore signatures + public transparency log                                     |

### What SLSA Does NOT Address

SLSA provenance does not replace traditional code signing for OS-level trust:

- **macOS Gatekeeper** will still quarantine unsigned binaries (Terminal strips the quarantine attribute automatically at extraction time)
- **Windows SmartScreen/WDAC** may flag unsigned `.exe` files on managed endpoints
- **Enterprise EDR tools** (CrowdStrike, Carbon Black) check Authenticode/codesign signatures, not SLSA provenance

If your organization requires OS-level code signing, please [open an issue](https://github.com/matlab/terminal-in-matlab/issues) to help us prioritize this.
