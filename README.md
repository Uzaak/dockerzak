# DockerZak

A persistent Docker development container with a curated set of pre-installed tools. Built on Debian Bookworm (glibc).

---

## Quick Start

```bash
# 1. Build the image (first run takes ~20–30 min — Flutter SDK is large)
make build

# 2a. Start the container — bare, no Claude auth
make up HOST_PATH=/absolute/path/to/your/project

# 2b. Or start with Claude Code auth inherited from your host (no login needed inside)
make up_full HOST_PATH=/absolute/path/to/your/project

# 3. Enter the container
make exec
```

You land as the `dev` user with all tools on `$PATH`. Your code is at `~/workspace`.

> **Claude auth:** `up_full` mounts `~/.claude` and `~/.claude.json` from your host so Claude Code
> works immediately without re-authenticating. Use plain `up` if you want a fully isolated environment.

---

## Prerequisites

- [Docker Engine](https://docs.docker.com/engine/install/)
- Docker Compose v2 (bundled with Docker Desktop; on Linux: `apt install docker-compose-plugin`)

---

## Makefile Reference

| Target         | Description                                              |
| -------------- | -------------------------------------------------------- |
| `make build`   | Build the Docker image                                   |
| `make up`      | Start the container (no optional mounts)                 |
| `make up_full` | Start with Claude auth + plugin marketplace pre-mounted  |
| `make exec`    | Open an interactive bash shell inside the container      |
| `make stop`    | Stop the container (state preserved, fast to resume)     |
| `make down`    | Stop and remove the container (workspace files are safe) |
| `make logs`    | Tail container logs                                      |
| `make clean`   | Remove container and image                               |
| `make help`    | Show all targets and current variable values             |

### Variables

All variables are optional overrides passed on the command line.

| Variable     | Default       | Description                                                                       |
| ------------ | ------------- | --------------------------------------------------------------------------------- |
| `HOST_PATH`  | `~/workspace` | Host directory mounted as `/home/dev/workspace` inside the container              |
| `CLAUDE_DIR` | _(not set)_   | Path to your `~/.claude` directory — enables Claude Code auth sharing (see below) |
| `PLUGIN_DIR` | _(not set)_   | Path to a local Claude Code plugin marketplace directory                          |

---

## Claude Code Auth Sharing

Claude Code is installed in the container but auth is **not shared by default**. Pass `CLAUDE_DIR` to inherit credentials, settings, and plugins from your host — no login or first-run setup needed:

```bash
make up HOST_PATH=/your/project CLAUDE_DIR=~/.claude
```

`CLAUDE_DIR` pulls in three mounts:

| What                                  | Why                                                                                                                                            |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.claude`                           | Credentials, settings, plugins, session history                                                                                                |
| `~/.claude.json`                      | First-run state (`numStartups`) — suppresses the setup wizard                                                                                  |
| `~/.claude` at its original host path | Plugin `installPath` entries in `installed_plugins.json` are stored as absolute host paths; this alias makes them resolve inside the container |

Without `CLAUDE_DIR`, Claude Code starts fresh and will walk you through login on first use.

---

## Local Plugin Marketplace

If you develop Claude Code plugins locally, mount the marketplace directory so the container can resolve them:

```bash
make up HOST_PATH=/your/project CLAUDE_DIR=~/.claude PLUGIN_DIR=~/Developer/ClaudeZak
```

---

## Volume Summary

| Mount                                                                      | Mode | Description                                         |
| -------------------------------------------------------------------------- | ---- | --------------------------------------------------- |
| `$HOST_PATH` → `/home/dev/workspace`                                       | rw   | Your code                                           |
| `/etc/ssl/certs/ca-certificates.crt` → `/etc/ssl/certs/host-ca-bundle.crt` | ro   | Host CA bundle for corporate TLS proxy              |
| `$CLAUDE_DIR` → `/home/dev/.claude`                                        | rw   | Claude config/auth _(only with `CLAUDE_DIR`)_       |
| `$CLAUDE_DIR` → `$CLAUDE_DIR`                                              | rw   | Claude plugin path alias _(only with `CLAUDE_DIR`)_ |
| `~/.claude.json` → `/home/dev/.claude.json`                                | rw   | Claude first-run state _(only with `CLAUDE_DIR`)_   |
| `$PLUGIN_DIR` → `$PLUGIN_DIR`                                              | ro   | Local plugin marketplace _(only with `PLUGIN_DIR`)_ |

---

## Installed Tools

| Tool                | Version       |
| ------------------- | ------------- |
| Go                  | latest stable |
| Node.js             | 20 LTS        |
| Java                | 17 (OpenJDK)  |
| PHP                 | 8.2           |
| Flutter             | latest stable |
| Docker CLI          | latest stable |
| Kubectl             | 1.30          |
| Helm                | latest stable |
| AWS CLI             | v2            |
| GitHub CLI          | latest stable |
| Composer            | latest        |
| Homebrew            | latest        |
| Air (Go hot-reload) | latest        |
| Claude Code         | latest        |
| rtk                 | latest        |

---

## Troubleshooting

**Container exits immediately**

```bash
docker logs dockerzak
```

**Workspace files show wrong owner / permission errors**
The `dev` user inside the container is UID 1000. Most Linux workstations default to UID 1000 — verify with `id -u`.

**"no such container: dockerzak"**
The container isn't running. Start it: `make up HOST_PATH=/your/path`

**Claude asks to log in even with `CLAUDE_DIR` set**
Make sure `~/.claude.json` exists on the host (`ls ~/.claude.json`). This file is created the first time you run `claude` interactively on the host.
