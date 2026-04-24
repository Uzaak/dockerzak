# =============================================================================
# DockerZak — Makefile
# =============================================================================
#
# Common variables can be overridden on the command line:
#   make up HOST_PATH=/absolute/path/to/code
#
# =============================================================================

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

# HOST_PATH: absolute path on the host mounted as the workspace inside the container.
# Defaults to ~/workspace. Override with: make up HOST_PATH=/your/path
HOST_PATH      ?= $(HOME)/workspace

# CLAUDE_DIR: optional path to the Claude Code config directory on the host.
# When set, mounts ~/.claude and ~/.claude.json so auth and settings are
# inherited from the host — no login or first-run setup needed inside the container.
# Example: make up CLAUDE_DIR=$(HOME)/.claude
CLAUDE_DIR     ?=

# CLAUDE_JSON: auto-derived from CLAUDE_DIR (same parent dir, .claude.json file).
# Override only if your .claude.json lives somewhere non-standard.
CLAUDE_JSON     = $(if $(CLAUDE_DIR),$(dir $(CLAUDE_DIR)).claude.json,)

# PLUGIN_DIR: optional path to a local Claude Code plugin marketplace directory.
# When set, the directory is bind-mounted at the same absolute path inside the
# container so that plugin installPaths in installed_plugins.json resolve.
# Example: make up PLUGIN_DIR=$(HOME)/Developer/ClaudeZak
PLUGIN_DIR     ?=

# CONTAINER_NAME: must match container_name in docker-compose.yml.
CONTAINER_NAME ?= dockerzak

# IMAGE_NAME: must match the image: field in docker-compose.yml.
IMAGE_NAME     ?= dockerzak:latest

# Internal: include override files only when the corresponding variable is set.
_CLAUDE_OVERRIDE = $(if $(CLAUDE_DIR),-f docker-compose.claude.yml,)
_PLUGIN_OVERRIDE = $(if $(PLUGIN_DIR),-f docker-compose.plugins.yml,)

# -----------------------------------------------------------------------------
# Guard: error if HOST_PATH was explicitly set to empty.
# -----------------------------------------------------------------------------
_check_host_path:
	@if [ -z "$(HOST_PATH)" ]; then \
		echo "ERROR: HOST_PATH is empty. Provide an absolute path:"; \
		echo "  make <target> HOST_PATH=/absolute/path/to/workspace"; \
		exit 1; \
	fi

# -----------------------------------------------------------------------------
# .PHONY
# -----------------------------------------------------------------------------
.PHONY: build up up_full exec stop down logs clean help _check_host_path

# -----------------------------------------------------------------------------
# Targets
# -----------------------------------------------------------------------------

## build: Build the Docker image from the local Dockerfile.
build:
	@echo ">>> Building image $(IMAGE_NAME) (UID=$(shell id -u), GID=$(shell id -g))..."
	@docker build \
		--build-arg USER_UID=$(shell id -u) \
		--build-arg USER_GID=$(shell id -g) \
		-t $(IMAGE_NAME) .

## up: Start the container in the background.
up: _check_host_path
	@echo ">>> Starting container $(CONTAINER_NAME) (workspace=$(HOST_PATH))..."
	@HOST_PATH=$(HOST_PATH) CLAUDE_DIR=$(CLAUDE_DIR) CLAUDE_JSON=$(CLAUDE_JSON) PLUGIN_DIR=$(PLUGIN_DIR) docker compose $(_CLAUDE_OVERRIDE) $(_PLUGIN_OVERRIDE) up -d

## up_full: Start the container with all optional mounts enabled (Claude auth + plugin marketplace).
## HOST_PATH is still required. CLAUDE_DIR and PLUGIN_DIR default to standard locations
## but can be overridden: make up_full HOST_PATH=... PLUGIN_DIR=/custom/path
up_full: _check_host_path
	$(eval _CLAUDE := $(or $(CLAUDE_DIR),$(HOME)/.claude))
	$(eval _PLUGIN := $(or $(PLUGIN_DIR),$(HOME)/Developer/ClaudeZak))
	@echo ">>> Starting container $(CONTAINER_NAME) with full mounts (workspace=$(HOST_PATH))..."
	@HOST_PATH=$(HOST_PATH) \
		CLAUDE_DIR=$(_CLAUDE) \
		CLAUDE_JSON=$(dir $(_CLAUDE)).claude.json \
		PLUGIN_DIR=$(_PLUGIN) \
		docker compose -f docker-compose.yml -f docker-compose.claude.yml -f docker-compose.plugins.yml up -d

## exec: Open an interactive bash shell inside the running container.
exec:
	@echo ">>> Opening shell in $(CONTAINER_NAME)..."
	@docker exec -it $(CONTAINER_NAME) bash

## stop: Stop the container without removing it (state is preserved).
stop:
	@echo ">>> Stopping $(CONTAINER_NAME)..."
	@docker compose stop

## down: Stop and remove the container (workspace files are safe — they're on the host).
down:
	@echo ">>> Removing container $(CONTAINER_NAME)..."
	@docker compose down

## logs: Tail the container logs.
logs:
	@echo ">>> Tailing logs for $(CONTAINER_NAME)..."
	@docker compose logs -f --tail=50 $(CONTAINER_NAME)

## clean: Stop, remove the container, and delete the image.
clean: down
	@echo ">>> Removing image $(IMAGE_NAME)..."
	@docker rmi $(IMAGE_NAME) || true

## help: List all available targets.
help:
	@echo ""
	@echo "DockerZak — available Makefile targets"
	@echo "======================================="
	@echo ""
	@echo "  build    Build the Docker image."
	@echo "  up       Start the container (no optional mounts).  Overrides: HOST_PATH  CLAUDE_DIR  PLUGIN_DIR"
	@echo "  up_full  Start the container with Claude auth + plugin marketplace pre-mounted."
	@echo "           Defaults: CLAUDE_DIR=$(HOME)/.claude  PLUGIN_DIR=$(HOME)/Developer/ClaudeZak"
	@echo "  exec     Open a bash shell inside the running container."
	@echo "  stop    Stop the container without removing it."
	@echo "  down    Stop and remove the container (workspace files are safe)."
	@echo "  logs    Tail container logs."
	@echo "  clean   Remove container and image."
	@echo "  help    Show this help."
	@echo ""
	@echo "Current values:"
	@echo "  HOST_PATH      = $(HOST_PATH)"
	@echo "  CLAUDE_DIR     = $(if $(CLAUDE_DIR),$(CLAUDE_DIR),(not set))"
	@echo "  PLUGIN_DIR     = $(if $(PLUGIN_DIR),$(PLUGIN_DIR),(not set))"
	@echo "  CONTAINER_NAME = $(CONTAINER_NAME)"
	@echo "  IMAGE_NAME     = $(IMAGE_NAME)"
	@echo ""
