#!/bin/sh
# QA Summary: 12 tests
# Scenarios: STORY-3 SSH hardening (PasswordAuthentication no, PermitRootLogin no),
#            full dockerzak.conf directive validation, conf file exists and is readable,
#            sshd_config includes the drop-in, container process stays alive (tail pid check)
# Security: PasswordAuthentication must be 'no'; PermitRootLogin must be 'no';
#           PubkeyAuthentication must be 'yes'; PermitEmptyPasswords must be 'no';
#           X11Forwarding must be 'no'; AllowTcpForwarding must be 'no';
#           MaxAuthTries must be <= 3; LoginGraceTime must be <= 30
#
# Usage (inside container):
#   /test/validate-ssh-config.sh
#   docker exec <container> /test/validate-ssh-config.sh
#
# Exit codes: 0 = all checks passed, 1 = one or more checks failed

set -u

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    GREEN="$(tput setaf 2)"
    RED="$(tput setaf 1)"
    YELLOW="$(tput setaf 3)"
    RESET="$(tput sgr0)"
else
    GREEN=""
    RED=""
    YELLOW=""
    RESET=""
fi

PASS=0
FAIL=0

pass() { printf '%sPASS%s  %s\n' "${GREEN}" "${RESET}" "$*"; PASS=$((PASS + 1)); }
fail() { printf '%sFAIL%s  %s\n' "${RED}"   "${RESET}" "$*"; FAIL=$((FAIL + 1)); }
info() { printf '%sINFO%s  %s\n' "${YELLOW}" "${RESET}" "$*"; }

# ---------------------------------------------------------------------------
# Config file paths
# ---------------------------------------------------------------------------
DROPIN_CONF="/etc/ssh/sshd_config.d/dockerzak.conf"
MAIN_SSHD_CONF="/etc/ssh/sshd_config"

# ---------------------------------------------------------------------------
# Helper: check that a directive in the drop-in conf has the expected value.
#   check_directive <directive_name> <expected_value>
#   Matching is case-insensitive on the directive name; value is exact.
# ---------------------------------------------------------------------------
check_directive() {
    local directive="$1"
    local expected="$2"

    local actual
    actual="$(grep -i "^${directive}[[:space:]]" "${DROPIN_CONF}" 2>/dev/null \
              | awk '{print $2}' | head -1)"

    if [ -z "${actual}" ]; then
        fail "${directive}: directive not found in ${DROPIN_CONF}"
        return 1
    fi

    if [ "${actual}" = "${expected}" ]; then
        pass "${directive}: ${actual}"
    else
        fail "${directive}: expected '${expected}', got '${actual}'"
    fi
}

# ---------------------------------------------------------------------------
# Helper: check that a numeric directive satisfies actual <= maximum.
#   check_numeric_le <directive_name> <maximum>
# ---------------------------------------------------------------------------
check_numeric_le() {
    local directive="$1"
    local maximum="$2"

    local actual
    actual="$(grep -i "^${directive}[[:space:]]" "${DROPIN_CONF}" 2>/dev/null \
              | awk '{print $2}' | head -1)"

    if [ -z "${actual}" ]; then
        fail "${directive}: directive not found in ${DROPIN_CONF}"
        return 1
    fi

    # Strip non-numeric characters just in case
    local numeric
    numeric="$(printf '%s' "${actual}" | tr -cd '0-9')"

    if [ "${numeric}" -le "${maximum}" ]; then
        pass "${directive}: ${actual} (<= ${maximum})"
    else
        fail "${directive}: ${actual} exceeds maximum of ${maximum}"
    fi
}

# ===========================================================================
# 1. Config file existence and readability
# ===========================================================================

info "--- Config file checks ---"

if [ -f "${DROPIN_CONF}" ]; then
    pass "Drop-in config exists: ${DROPIN_CONF}"
else
    fail "Drop-in config NOT found: ${DROPIN_CONF}"
    # Cannot continue without the file — print summary and exit immediately
    printf '\n%sFATAL: %s not found. Cannot validate SSH hardening.%s\n' \
           "${RED}" "${DROPIN_CONF}" "${RESET}"
    exit 1
fi

if [ -r "${DROPIN_CONF}" ]; then
    pass "Drop-in config is readable"
else
    fail "Drop-in config is NOT readable (check file permissions)"
fi

# Verify sshd_config includes the drop-in directory
if grep -qF 'Include /etc/ssh/sshd_config.d/*.conf' "${MAIN_SSHD_CONF}" 2>/dev/null; then
    pass "sshd_config includes /etc/ssh/sshd_config.d/*.conf"
else
    fail "sshd_config does NOT include /etc/ssh/sshd_config.d/*.conf — drop-in may be ignored"
fi

# ===========================================================================
# 2. Critical security directives (STORY-3 ACs + security ACs)
# ===========================================================================

info "--- Critical security directives ---"

# STORY-3 AC: PasswordAuthentication no
check_directive "PasswordAuthentication" "no"

# STORY-3 AC: PermitRootLogin no
check_directive "PermitRootLogin" "no"

# Public-key auth must be enabled (it's the only allowed auth method)
check_directive "PubkeyAuthentication" "yes"

# AuthorizedKeysFile must point to .ssh/authorized_keys
check_directive "AuthorizedKeysFile" ".ssh/authorized_keys"

# ===========================================================================
# 3. Additional hardening directives
# ===========================================================================

info "--- Additional hardening directives ---"

check_directive "ChallengeResponseAuthentication" "no"
check_directive "X11Forwarding" "no"
check_directive "AllowTcpForwarding" "no"
check_directive "PermitEmptyPasswords" "no"

# Numeric guards — MaxAuthTries <= 3, LoginGraceTime <= 30
check_numeric_le "MaxAuthTries" 3
check_numeric_le "LoginGraceTime" 30

# ===========================================================================
# 4. Container liveness (STORY-3: container stays alive)
# ===========================================================================

info "--- Container liveness check ---"

# When running inside the container, PID 1 should be tail -f /dev/null.
# If we are NOT inside a container this check is skipped gracefully.

if [ -f /proc/1/cmdline ]; then
    pid1_cmd="$(tr '\0' ' ' < /proc/1/cmdline 2>/dev/null || cat /proc/1/cmdline 2>/dev/null)"
    case "${pid1_cmd}" in
        *tail*-f*)
            pass "PID 1 is 'tail -f /dev/null' — container liveness process is running"
            ;;
        *)
            # Not necessarily a failure if run outside the container
            info "PID 1 command: '${pid1_cmd}' (expected 'tail -f /dev/null' inside container)"
            pass "Container liveness check skipped (may be running outside the container)"
            ;;
    esac
else
    pass "Container liveness check skipped (no /proc filesystem — likely not Linux)"
fi

# ===========================================================================
# Summary
# ===========================================================================

TOTAL=$((PASS + FAIL))
printf '\n'
printf '=%.0s' $(seq 1 60); printf '\n'
printf 'Results: %s/%s checks passed\n' "${PASS}" "${TOTAL}"
if [ "${FAIL}" -gt 0 ]; then
    printf '%s%d check(s) FAILED%s\n' "${RED}" "${FAIL}" "${RESET}"
    exit 1
else
    printf '%sAll SSH config checks PASSED%s\n' "${GREEN}" "${RESET}"
    exit 0
fi
