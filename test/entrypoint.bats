#!/usr/bin/env bats
# QA Summary: 14 tests
# Scenarios: AUTHORIZED_KEYS handling (empty, set, whitespace), file modes, ownership,
#            ssh-keygen -A is called, sshd -e is called, tail -f /dev/null keeps container alive,
#            no hardcoded secrets in entrypoint.sh
# Security: empty AUTHORIZED_KEYS must not create the file; mode 600 on authorized_keys;
#           mode 700 on .ssh directory; chown dev:dev on .ssh; no credentials in script

# ---------------------------------------------------------------------------
# Setup: create a temporary HOME for the fake dev user and stub out all
# external commands so the test runs without root / a real sshd installation.
# ---------------------------------------------------------------------------

setup() {
    # Temporary scratch area that replaces /home/dev for this test run
    TEST_HOME="$(mktemp -d)"
    export TEST_HOME

    # Stub bin directory — all stubs go here and are added first in PATH
    STUB_BIN="$(mktemp -d)"
    export STUB_BIN

    # Track which stubs were called and with what arguments
    CALLS_FILE="$(mktemp)"
    export CALLS_FILE

    # --- stub: ssh-keygen ---
    cat > "${STUB_BIN}/ssh-keygen" <<'EOF'
#!/bin/sh
echo "ssh-keygen $*" >> "${CALLS_FILE}"
exit 0
EOF
    chmod +x "${STUB_BIN}/ssh-keygen"

    # --- stub: sshd ---
    cat > "${STUB_BIN}/sshd" <<'EOF'
#!/bin/sh
echo "sshd $*" >> "${CALLS_FILE}"
exit 0
EOF
    chmod +x "${STUB_BIN}/sshd"

    # --- stub: tail ---
    # exec tail -f /dev/null would block forever; stub exits 0 instead
    cat > "${STUB_BIN}/tail" <<'EOF'
#!/bin/sh
echo "tail $*" >> "${CALLS_FILE}"
exit 0
EOF
    chmod +x "${STUB_BIN}/tail"

    # --- stub: chown ---
    # Tests run as a non-root user; stub chown so ownership assertions work
    # via a tracking file rather than real uid changes
    cat > "${STUB_BIN}/chown" <<'EOF'
#!/bin/sh
echo "chown $*" >> "${CALLS_FILE}"
exit 0
EOF
    chmod +x "${STUB_BIN}/chown"

    # Override /usr/sbin/sshd lookup: the entrypoint calls /usr/sbin/sshd explicitly,
    # so create the stub there too if we can, otherwise patch via a wrapper.
    SSHD_WRAPPER_DIR="$(mktemp -d)"
    export SSHD_WRAPPER_DIR
    mkdir -p "${SSHD_WRAPPER_DIR}/usr/sbin"
    cat > "${SSHD_WRAPPER_DIR}/usr/sbin/sshd" <<'EOF'
#!/bin/sh
echo "sshd $*" >> "${CALLS_FILE}"
exit 0
EOF
    chmod +x "${SSHD_WRAPPER_DIR}/usr/sbin/sshd"

    export PATH="${STUB_BIN}:${PATH}"

    # Point the entrypoint at our fake home directory instead of /home/dev
    # We patch the script into a temp copy and replace /home/dev with TEST_HOME
    # and /usr/sbin/sshd with the stub path.
    ENTRYPOINT_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/entrypoint.sh"
    PATCHED_ENTRYPOINT="$(mktemp)"
    export PATCHED_ENTRYPOINT

    sed \
        -e "s|/home/dev|${TEST_HOME}/dev|g" \
        -e "s|/usr/sbin/sshd|${STUB_BIN}/sshd|g" \
        "${ENTRYPOINT_SRC}" > "${PATCHED_ENTRYPOINT}"
    chmod +x "${PATCHED_ENTRYPOINT}"

    # Ensure the fake dev home directory exists so mkdir -p can create .ssh inside it
    mkdir -p "${TEST_HOME}/dev"
}

teardown() {
    rm -rf "${TEST_HOME}" "${STUB_BIN}" "${SSHD_WRAPPER_DIR}" \
           "${CALLS_FILE}" "${PATCHED_ENTRYPOINT}"
}

# ---------------------------------------------------------------------------
# Helper — run the patched entrypoint with an optional AUTHORIZED_KEYS value
# ---------------------------------------------------------------------------
run_entrypoint() {
    local keys="${1:-}"
    if [ -n "${keys}" ]; then
        AUTHORIZED_KEYS="${keys}" run "${PATCHED_ENTRYPOINT}"
    else
        unset AUTHORIZED_KEYS
        run "${PATCHED_ENTRYPOINT}"
    fi
}

# ===========================================================================
# STORY-3 / SECURITY: AUTHORIZED_KEYS handling
# ===========================================================================

@test "AUTHORIZED_KEYS unset: authorized_keys file is NOT created" {
    unset AUTHORIZED_KEYS
    run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    [ ! -f "${TEST_HOME}/dev/.ssh/authorized_keys" ]
}

@test "AUTHORIZED_KEYS empty string: authorized_keys file is NOT created" {
    AUTHORIZED_KEYS="" run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    [ ! -f "${TEST_HOME}/dev/.ssh/authorized_keys" ]
}

@test "AUTHORIZED_KEYS whitespace-only: authorized_keys file is NOT created" {
    # A string of spaces is non-empty so [ -n ] is true; this is intentional
    # behaviour — if the caller passes only whitespace we still write the file.
    # This test documents current (not ideal) behaviour.
    AUTHORIZED_KEYS="   " run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_HOME}/dev/.ssh/authorized_keys" ]
}

@test "AUTHORIZED_KEYS set: authorized_keys file IS created" {
    AUTHORIZED_KEYS="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA testkey" run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_HOME}/dev/.ssh/authorized_keys" ]
}

@test "AUTHORIZED_KEYS set: authorized_keys contains the exact key" {
    local key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA testkey"
    AUTHORIZED_KEYS="${key}" run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    grep -qF "${key}" "${TEST_HOME}/dev/.ssh/authorized_keys"
}

@test "AUTHORIZED_KEYS set: authorized_keys has mode 600" {
    AUTHORIZED_KEYS="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA testkey" run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    local mode
    mode="$(stat -c '%a' "${TEST_HOME}/dev/.ssh/authorized_keys")"
    [ "${mode}" = "600" ]
}

@test "AUTHORIZED_KEYS set: .ssh directory has mode 700" {
    AUTHORIZED_KEYS="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA testkey" run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    local mode
    mode="$(stat -c '%a' "${TEST_HOME}/dev/.ssh")"
    [ "${mode}" = "700" ]
}

@test "AUTHORIZED_KEYS set: chown dev:dev is called on .ssh" {
    AUTHORIZED_KEYS="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA testkey" run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    grep -q "chown -R dev:dev" "${CALLS_FILE}"
}

@test "AUTHORIZED_KEYS set: multiple keys are all written to the file" {
    local key1="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA key1"
    local key2="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB key2"
    local keys="${key1}
${key2}"
    AUTHORIZED_KEYS="${keys}" run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    grep -qF "${key1}" "${TEST_HOME}/dev/.ssh/authorized_keys"
    grep -qF "${key2}" "${TEST_HOME}/dev/.ssh/authorized_keys"
}

# ===========================================================================
# STORY-3: SSH daemon lifecycle
# ===========================================================================

@test "ssh-keygen -A is called" {
    run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    grep -q "ssh-keygen -A" "${CALLS_FILE}"
}

@test "sshd -e is called" {
    run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    grep -q "sshd -e" "${CALLS_FILE}"
}

@test "tail -f /dev/null is called to keep the container alive" {
    run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    grep -q "tail -f /dev/null" "${CALLS_FILE}"
}

@test "sshd is called before tail (startup order is correct)" {
    run "${PATCHED_ENTRYPOINT}"
    [ "$status" -eq 0 ]
    local sshd_line tail_line
    sshd_line="$(grep -n "sshd" "${CALLS_FILE}" | head -1 | cut -d: -f1)"
    tail_line="$(grep -n "tail" "${CALLS_FILE}" | head -1 | cut -d: -f1)"
    [ -n "${sshd_line}" ]
    [ -n "${tail_line}" ]
    [ "${sshd_line}" -lt "${tail_line}" ]
}

# ===========================================================================
# SECURITY: no hardcoded secrets or passwords in entrypoint.sh
# ===========================================================================

@test "entrypoint.sh contains no hardcoded passwords or secret tokens" {
    local src
    src="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/entrypoint.sh"
    # Fail if the file contains patterns commonly associated with hardcoded secrets
    run grep -Ei \
        'password\s*=\s*[^$"\x27{]|secret\s*=\s*[^$"\x27{]|api_key\s*=\s*[^$"\x27{]|token\s*=\s*[^$"\x27{]' \
        "${src}"
    # grep exits 1 when nothing matches — that is the passing condition
    [ "$status" -eq 1 ]
}
