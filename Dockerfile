# =============================================================================
# DockerZak — Development Container
# =============================================================================
#
# Base image: debian:bookworm-slim
#
# NOTE — Alpine was explicitly rejected as the base image for the following
# reasons:
#   1. musl libc incompatibility: Alpine uses musl instead of glibc. The Go
#      toolchain distributed by dl.google.com is compiled against glibc, and
#      many Go CGO-enabled binaries assume glibc symbol availability.
#   2. Java JVM: The OpenJDK JVM (and most JVM distributions) are built and
#      tested against glibc. Running them on musl leads to subtle runtime
#      failures and is not a supported configuration for production workloads.
#   3. Flutter / Dart SDK: Dart's prebuilt SDK binaries are glibc-linked.
#      Flutter additionally depends on several native shared libraries that
#      expect glibc semantics (e.g., dlopen behaviour differences).
#   4. Homebrew / Linuxbrew: Homebrew on Linux explicitly requires glibc >= 2.13
#      and is not supported on Alpine / musl-based distributions.
#
# debian:bookworm-slim provides a minimal glibc environment that satisfies all
# of the above requirements while keeping image layers small.
# =============================================================================

FROM debian:bookworm-slim

# ---------------------------------------------------------------------------
# Build-time environment — suppress interactive prompts for all apt operations
# ---------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# System dependencies
#
# Packages installed here are prerequisites for the runtimes that follow:
#   - ca-certificates, gnupg, curl, wget : TLS trust store + download tooling
#   - git                                : source control (used by runtimes/tools)
#   - build-essential                    : gcc/g++/make for native modules
#   - libssl-dev, zlib1g-dev             : common native-module headers
#   - procps, lsof, net-tools            : diagnostic utilities
#   - locales                            : set en_US.UTF-8 locale
#   - openssh-server                     : SSH daemon for remote access
# ---------------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      gnupg \
      curl \
      wget \
      git \
      unzip \
      xz-utils \
      build-essential \
      libssl-dev \
      zlib1g-dev \
      libffi-dev \
      libreadline-dev \
      procps \
      lsof \
      net-tools \
      locales \
      sudo \
      lsb-release \
 && sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
 && locale-gen \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# Go 1.22 — installed from official tarball (dl.google.com)
#
# The tarball is extracted to /usr/local, placing the toolchain at
# /usr/local/go.  The go binary is therefore at /usr/local/go/bin/go.
# GOPATH is set to /home/dev/go so that `go install`-ed tools land in the
# dev user's home directory.
# ---------------------------------------------------------------------------
RUN set -eux; \
    GO_VERSION="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1 | sed 's/^go//')"; \
    ARCH="$(dpkg --print-architecture)"; \
    case "${ARCH}" in \
      amd64)   GO_ARCH="amd64" ;; \
      arm64)   GO_ARCH="arm64" ;; \
      armhf)   GO_ARCH="armv6l" ;; \
      *)       echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac; \
    curl -fsSL "https://dl.google.com/go/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" \
      -o /tmp/go.tar.gz; \
    tar -C /usr/local -xzf /tmp/go.tar.gz; \
    rm /tmp/go.tar.gz

ENV PATH=/usr/local/go/bin:$PATH

# ---------------------------------------------------------------------------
# Node.js 20 LTS — installed via NodeSource setup script
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Java 17 LTS — OpenJDK from Debian bookworm repository
# (Java 21 requires bookworm-backports; Java 17 is the default LTS in bookworm)
# ---------------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-17-jdk \
 && rm -rf /var/lib/apt/lists/*

# JAVA_HOME is architecture-aware: resolve the actual JVM path at build time
RUN ARCH="$(dpkg --print-architecture)"; \
    JAVA_HOME_PATH="$(ls -d /usr/lib/jvm/java-17-openjdk-${ARCH} 2>/dev/null \
      || ls -d /usr/lib/jvm/java-17-openjdk-* | head -1)"; \
    echo "JAVA_HOME=${JAVA_HOME_PATH}" >> /etc/environment; \
    ln -sfn "${JAVA_HOME_PATH}" /usr/lib/jvm/java-17-openjdk-current
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-current
ENV PATH=$JAVA_HOME/bin:$PATH

# ---------------------------------------------------------------------------
# PHP — Debian bookworm ships php8.2 in its main repository.
#
# NOTE: php8.3 is NOT available in the official debian:bookworm package
# repositories (bookworm = Debian 12, which ships php8.2 as the default PHP
# version). If php8.3 is strictly required, add the ondrej/php PPA. For now
# we install the latest available version (8.2) with the most common extensions.
# ---------------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      php-cli \
      php-common \
      php-curl \
      php-mbstring \
      php-xml \
      php-zip \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Non-root dev user
#
# UID/GID 1000 is the conventional first non-system user on Debian/Ubuntu and
# matches the default host UID on most Linux developer workstations, which
# avoids bind-mount permission issues when running the container locally.
#
# macOS often uses GID 20 (staff), which collides with Debian's reserved GID 20
# (dialout). Reuse the existing group instead of groupadd in that case.
# ---------------------------------------------------------------------------
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    if getent group "${USER_GID}" > /dev/null 2>&1; then \
      PRIMARY_GROUP=$(getent group "${USER_GID}" | cut -d: -f1); \
    else \
      groupadd --gid "${USER_GID}" dev; \
      PRIMARY_GROUP=dev; \
    fi; \
    useradd \
      --uid "${USER_UID}" \
      --gid "${PRIMARY_GROUP}" \
      --create-home \
      --home-dir /home/dev \
      --shell /bin/bash \
      dev; \
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev; \
    chmod 0440 /etc/sudoers.d/dev
# NOTE: Full sudo granted for developer convenience (install packages, etc).
# The Docker socket is NOT mounted by default — do not mount /var/run/docker.sock
# unless you understand that it gives root-equivalent access to the host.

# ---------------------------------------------------------------------------
# GOPATH — user-scoped Go workspace lives under the dev home directory
# ---------------------------------------------------------------------------
ENV GOPATH=/home/dev/go

RUN mkdir -p /home/dev/go/bin /home/dev/go/src /home/dev/go/pkg \
 && chown -R "${USER_UID}:${USER_GID}" /home/dev/go

# PATH updated with Go workspace bin dir
ENV PATH=/usr/local/go/bin:/home/dev/go/bin:$PATH

# =============================================================================
# CLI Tools & Package Managers (STORY-2)
# =============================================================================

# ---------------------------------------------------------------------------
# Docker CLI (client only, no daemon)
# ---------------------------------------------------------------------------
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Kubectl
# ---------------------------------------------------------------------------
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
 && chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
 && echo \
      "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
      https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
      > /etc/apt/sources.list.d/kubernetes.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends kubectl \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Helm — latest release resolved from GitHub at build time
# ---------------------------------------------------------------------------
RUN set -eux; \
    HELM_VERSION="$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest \
      | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')"; \
    ARCH="$(dpkg --print-architecture)"; \
    case "${ARCH}" in \
      amd64) HELM_ARCH="amd64" ;; \
      arm64) HELM_ARCH="arm64" ;; \
      *)     echo "Unsupported arch: ${ARCH}" && exit 1 ;; \
    esac; \
    HELM_FILE="helm-v${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"; \
    curl -fsSL "https://get.helm.sh/${HELM_FILE}" -o "/tmp/${HELM_FILE}"; \
    tar -xzf "/tmp/${HELM_FILE}" -C /tmp; \
    mv "/tmp/linux-${HELM_ARCH}/helm" /usr/local/bin/helm; \
    chmod +x /usr/local/bin/helm; \
    rm -rf "/tmp/${HELM_FILE}" "/tmp/linux-${HELM_ARCH}"

# ---------------------------------------------------------------------------
# AWS CLI — installed via Debian apt package
# ---------------------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends awscli \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# GitHub CLI (gh)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
      https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Composer (PHP package manager)
# Verifies installer checksum against composer.github.io/installer.sig
# ---------------------------------------------------------------------------
RUN php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');" \
 && php -r " \
      \$expected = trim(file_get_contents('https://composer.github.io/installer.sig')); \
      \$actual   = hash_file('sha384', '/tmp/composer-setup.php'); \
      if (\$expected !== \$actual) { \
          fwrite(STDERR, 'Composer installer checksum mismatch' . PHP_EOL); \
          unlink('/tmp/composer-setup.php'); \
          exit(1); \
      } \
      echo 'Installer verified' . PHP_EOL; \
    " \
 && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm /tmp/composer-setup.php

# ---------------------------------------------------------------------------
# Homebrew / Linuxbrew — must run as non-root user
# Installed to /home/dev/.linuxbrew
# ---------------------------------------------------------------------------
USER dev

ENV HOMEBREW_PREFIX=/home/dev/.linuxbrew \
    HOMEBREW_CELLAR=/home/dev/.linuxbrew/Cellar \
    HOMEBREW_REPOSITORY=/home/dev/.linuxbrew/Homebrew

RUN NONINTERACTIVE=1 bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/dev/.linuxbrew/bin:/home/dev/.linuxbrew/sbin:${PATH}"

# ---------------------------------------------------------------------------
# Air (Go hot-reload) — latest release, installs to /home/dev/go/bin/air
# ---------------------------------------------------------------------------
RUN go install github.com/air-verse/air@latest

# ---------------------------------------------------------------------------
# rtk — CLI proxy that reduces LLM token consumption by filtering command output
# Installs to /home/dev/.local/bin via the official install script
# After container start, run: rtk init -g  (wires up Claude Code hook)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh

ENV PATH="/home/dev/.local/bin:${PATH}"

# =============================================================================
# Flutter, Claude Code & Entrypoint (STORY-3)
# =============================================================================

USER root

# ---------------------------------------------------------------------------
# Flutter SDK — tracks the stable channel (latest stable release at build time)
# ---------------------------------------------------------------------------
RUN git clone https://github.com/flutter/flutter.git /opt/flutter --depth 1 -b stable \
 && chown -R "${USER_UID}:${USER_GID}" /opt/flutter

ENV PATH="/opt/flutter/bin:${PATH}"

# Pre-cache the Dart SDK and commonly used artifacts (excluding web/fuchsia/linux-desktop)
# Run as dev so flutter writes caches to dev-owned directories
USER dev
RUN flutter precache --no-web --no-fuchsia
USER root

# ---------------------------------------------------------------------------
# Claude Code (global npm install)
# Authentication is interactive — run `claude` after starting the container
# ---------------------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code

# ---------------------------------------------------------------------------
# Workspace mount point
#
# IMPORTANT: /dev is the kernel device filesystem automatically mounted by
# Docker at runtime (contains /dev/null, /dev/urandom, etc.). Mounting a
# volume to /dev would overwrite those device nodes and break the container.
#
# Use /home/dev/workspace as the mount point instead:
#   docker run -v /your/host/path:/home/dev/workspace ...
# ---------------------------------------------------------------------------
RUN mkdir -p /home/dev/workspace \
 && chown "${USER_UID}:${USER_GID}" /home/dev/workspace

# ---------------------------------------------------------------------------
# Container-level Claude Code instructions
#
# DOCKER_CLAUDE.md is copied to /home/dev/CLAUDE.md so Claude Code picks it
# up via directory tree-walking for every project under /home/dev/workspace/.
# This location is NOT shadowed by the CLAUDE_DIR volume mount (which targets
# /home/dev/.claude, not /home/dev directly).
# ---------------------------------------------------------------------------
COPY --chown=${USER_UID}:${USER_GID} DOCKER_CLAUDE.md /home/dev/CLAUDE.md

USER dev
WORKDIR /home/dev

# Set NODE_EXTRA_CA_CERTS so Claude Code (and any Node.js tool) can connect
# through corporate TLS-intercepting proxies. The CA bundle is mounted from
# the host at runtime via docker-compose.yml.
RUN echo 'export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/host-ca-bundle.crt' >> /home/dev/.bashrc \
 && echo '[ -f ~/.rtk-initialized ] || { rtk init -g 2>/dev/null && touch ~/.rtk-initialized; }' >> /home/dev/.bashrc

# Keep the container alive indefinitely.
# Access it with: docker exec -it dockerzak bash
CMD ["tail", "-f", "/dev/null"]
