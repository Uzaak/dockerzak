#!/bin/sh
# entrypoint.sh — DockerZak container entrypoint
# Runs as root; sshd requires root to bind port 22 and read host keys.
set -e

# ---------------------------------------------------------------------------
# Authorised SSH keys
# If the AUTHORIZED_KEYS environment variable is set, write it into the dev
# user's authorized_keys file with the correct permissions so that public-key
# authentication works on first boot without rebuilding the image.
#
# Security notes:
#   - Written atomically via tmp file + mv to avoid partial-key states on
#     interrupted writes.
#   - Keys are written verbatim from the env var; SSH command= prefix options
#     are passed through (valid use case for restricted keys).
#   - Whitespace-only values are treated as "set but empty" and skipped.
# ---------------------------------------------------------------------------
if [ -n "${AUTHORIZED_KEYS}" ] && [ "$(printf '%s' "${AUTHORIZED_KEYS}" | tr -d '[:space:]')" != "" ]; then
    # Reject suspiciously large values (> 64KB) to prevent disk-fill via env var
    KEY_LEN=$(printf '%s' "${AUTHORIZED_KEYS}" | wc -c)
    if [ "${KEY_LEN}" -gt 65536 ]; then
        echo "ERROR: AUTHORIZED_KEYS exceeds 64KB (${KEY_LEN} bytes). Refusing to write." >&2
        exit 1
    fi

    mkdir -p /home/dev/.ssh
    chmod 700 /home/dev/.ssh

    # Atomic write: write to tmp then rename — safe against interrupted containers
    printf '%s\n' "${AUTHORIZED_KEYS}" > /home/dev/.ssh/authorized_keys.tmp
    mv /home/dev/.ssh/authorized_keys.tmp /home/dev/.ssh/authorized_keys

    chmod 600 /home/dev/.ssh/authorized_keys
    chown -R dev:dev /home/dev/.ssh
else
    echo "INFO: AUTHORIZED_KEYS not set — SSH key authentication unavailable." >&2
    echo "INFO: Use 'docker exec -it <container> bash' to access the container." >&2
fi

# ---------------------------------------------------------------------------
# SSH host keys
# Generate any missing host key types (ed25519, rsa, ecdsa, ...).
# This is a no-op for key types that already exist on the image or a volume.
# To persist host keys across container restarts (avoids TOFU warnings),
# bind-mount a host directory to /etc/ssh and pre-populate host keys there.
# ---------------------------------------------------------------------------
ssh-keygen -A

# ---------------------------------------------------------------------------
# Workspace mount check — warn if no volume is mounted
# Files written to an unmounted workspace are lost on 'docker rm'.
# ---------------------------------------------------------------------------
if ! mountpoint -q /home/dev/workspace 2>/dev/null; then
    echo "WARNING: /home/dev/workspace is NOT a mounted volume." >&2
    echo "WARNING: Any files written there will be LOST when the container is removed." >&2
    echo "WARNING: Run with: -v /your/host/path:/home/dev/workspace" >&2
fi

# ---------------------------------------------------------------------------
# Start sshd in foreground as PID 1
#
# -D  : foreground mode — sshd does not daemonize; stays as PID 1
# -e  : log to stderr — captured by 'docker logs'
#
# sshd handles SIGTERM gracefully: it closes active sessions and exits
# cleanly. This replaces the previous 'tail -f /dev/null' pattern, which
# did not propagate signals or allow graceful session teardown.
# ---------------------------------------------------------------------------
exec /usr/sbin/sshd -D -e
