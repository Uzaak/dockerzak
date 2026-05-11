# Design: Add rtk + un-pin tool versions in DockerZak

**Date:** 2026-05-11
**Status:** Approved

---

## Summary

Two related changes to `Dockerfile`:

1. **Add rtk** — install the rtk CLI proxy (reduces LLM token consumption 60–90%) using its official install script, user-scoped to `/home/dev/.local/bin`.
2. **Un-pin Go, Flutter, Air, Helm** — resolve latest stable versions at build time instead of hardcoding specific versions.

No changes to `docker-compose.yml`, Makefile, entrypoint, or compose overrides.

---

## rtk Installation

**What:** rtk is a single Rust binary that intercepts CLI command output and filters/compresses it before it reaches Claude's context window. It integrates with Claude Code via `rtk init -g`.

**How:** Use rtk's official install script. It resolves the latest release from GitHub, downloads the appropriate binary for the current architecture (amd64/arm64), and places it at `$HOME/.local/bin/rtk`.

**Location in Dockerfile:** After the Air install step, still running as `dev` user.

```dockerfile
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
```

**PATH:** Add a single `ENV` line so rtk is immediately available:

```dockerfile
ENV PATH="/home/dev/.local/bin:${PATH}"
```

**Version:** Latest (not pinned). The install script always fetches the latest release.

**Security note:** The install script has no checksum verification. This is consistent with Homebrew's own install script and accepted by the user as a trade-off for simplicity.

---

## Un-pinning Tool Versions

All four tools resolve their latest version at Docker build time. This means rebuilding the image (`make build`) will pull newer versions automatically.

### Go

Remove the hardcoded `GO_VERSION` env var. Resolve the current stable version string from `https://go.dev/VERSION?m=text` at build time, strip the leading `go` prefix, then download the tarball.

```dockerfile
RUN set -eux; \
    GO_VERSION="$(curl -fsSL https://go.dev/VERSION?m=text | head -1 | sed 's/^go//')"; \
    ARCH="$(dpkg --print-architecture)"; \
    ...
```

### Flutter

Change `git clone -b ${FLUTTER_VERSION}` to `git clone -b stable`. Remove the `FLUTTER_VERSION` env var. The `stable` branch always points to the latest stable Flutter release.

```dockerfile
RUN git clone https://github.com/flutter/flutter.git /opt/flutter --depth 1 -b stable
```

### Air

Change `@v1.61.7` to `@latest`:

```dockerfile
RUN go install github.com/air-verse/air@latest
```

### Helm

Remove the hardcoded `HELM_VERSION` env var and the checksum verification step (no official per-release checksums via the GitHub API). Resolve the latest release tag from GitHub at build time:

```dockerfile
RUN set -eux; \
    HELM_VERSION="$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest \
      | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')"; \
    ...
```

Drop the `sha256sum` check. Helm does publish checksums per release, but verifying them requires knowing the version string first — at that point the checksum file is fetched from the same CDN as the binary, which provides no meaningful supply-chain protection. The user has accepted "latest without pinning" across all tools.

---

## README

Add rtk to the Installed Tools table:

| Tool | Version |
|------|---------|
| rtk  | latest  |

Update Go, Flutter, Air, and Helm rows to show `latest` instead of pinned versions.

---

## Out of Scope

- `rtk init -g` (Claude Code hook setup) — interactive, run by the user after container start
- Changes to `docker-compose.yml`, Makefile, entrypoint, or compose overrides
- Installing Rust/Cargo toolchain
