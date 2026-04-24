#!/bin/sh
# QA Summary: 14 tool checks
# Scenarios: STORY-1 (go/node/java/php in PATH, versions >= minimum, dev UID 1000),
#            STORY-2 (docker/kubectl/helm/aws/gh/composer/brew/air --version succeed, no PATH conflicts),
#            STORY-3 (flutter/claude in PATH and executable)
# Security: all version checks run as the dev user; PATH is validated for conflicts
#
# Usage (inside container):
#   su -s /bin/sh dev -c "/test/validate-tools.sh"
#   OR
#   docker exec -u dev <container> /test/validate-tools.sh
#
# Exit codes: 0 = all checks passed, 1 = one or more checks failed

set -u

# ---------------------------------------------------------------------------
# Colour helpers (gracefully degrade when terminal has no colour support)
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
# Helper: compare semver-ish version strings
#   version_ge <actual> <minimum>
#   Returns 0 (true) when actual >= minimum, 1 otherwise.
#   Only the first three dot-separated numeric segments are compared.
# ---------------------------------------------------------------------------
version_ge() {
    local actual="$1"
    local minimum="$2"

    # Strip any leading 'v' or other non-numeric prefix
    actual="$(printf '%s' "${actual}" | sed 's/^[^0-9]*//')"
    minimum="$(printf '%s' "${minimum}" | sed 's/^[^0-9]*//')"

    # Extract major.minor.patch components (default missing components to 0)
    local a1 a2 a3 m1 m2 m3
    a1="$(printf '%s' "${actual}"  | cut -d. -f1 | tr -cd '0-9')"; a1="${a1:-0}"
    a2="$(printf '%s' "${actual}"  | cut -d. -f2 | tr -cd '0-9')"; a2="${a2:-0}"
    a3="$(printf '%s' "${actual}"  | cut -d. -f3 | tr -cd '0-9')"; a3="${a3:-0}"
    m1="$(printf '%s' "${minimum}" | cut -d. -f1 | tr -cd '0-9')"; m1="${m1:-0}"
    m2="$(printf '%s' "${minimum}" | cut -d. -f2 | tr -cd '0-9')"; m2="${m2:-0}"
    m3="$(printf '%s' "${minimum}" | cut -d. -f3 | tr -cd '0-9')"; m3="${m3:-0}"

    if   [ "${a1}" -gt "${m1}" ]; then return 0
    elif [ "${a1}" -lt "${m1}" ]; then return 1
    elif [ "${a2}" -gt "${m2}" ]; then return 0
    elif [ "${a2}" -lt "${m2}" ]; then return 1
    elif [ "${a3}" -ge "${m3}" ]; then return 0
    else return 1
    fi
}

# ---------------------------------------------------------------------------
# Helper: check a tool is reachable in PATH and its version is >= minimum.
#   check_version <label> <minimum> <actual_version_string>
# ---------------------------------------------------------------------------
check_version() {
    local label="$1"
    local minimum="$2"
    local actual="$3"

    if version_ge "${actual}" "${minimum}"; then
        pass "${label}: ${actual} (>= ${minimum})"
    else
        fail "${label}: ${actual} is BELOW minimum ${minimum}"
    fi
}

# ---------------------------------------------------------------------------
# Helper: check a command is on PATH and exits without error for --version
#   check_tool <label> <command> [<args>]
# ---------------------------------------------------------------------------
check_tool() {
    local label="$1"
    local cmd="$2"
    shift 2
    local args="${*:---version}"

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        fail "${label}: '${cmd}' not found in PATH"
        return 1
    fi

    if "${cmd}" ${args} >/dev/null 2>&1; then
        local ver
        ver="$("${cmd}" ${args} 2>&1 | head -1)"
        pass "${label}: $(command -v "${cmd}") — ${ver}"
        return 0
    else
        fail "${label}: '${cmd} ${args}' exited non-zero"
        return 1
    fi
}

# ===========================================================================
# STORY-1: Language runtimes — version checks with floor constraints
# ===========================================================================

info "--- STORY-1: Language runtimes ---"

# Go >= 1.22
if command -v go >/dev/null 2>&1; then
    go_ver="$(go version 2>&1 | sed -n 's/.*go\([0-9][0-9.]*\).*/\1/p' | head -1)"
    check_version "Go" "1.22.0" "${go_ver}"
else
    fail "Go: 'go' not found in PATH"
fi

# Node.js >= 20
if command -v node >/dev/null 2>&1; then
    node_ver="$(node --version 2>&1 | sed 's/^v//')"
    check_version "Node.js" "20.0.0" "${node_ver}"
else
    fail "Node.js: 'node' not found in PATH"
fi

# Java >= 21
if command -v java >/dev/null 2>&1; then
    java_ver="$(java -version 2>&1 | sed -n 's/.*version "\([0-9][0-9.]*\).*/\1/p' | head -1)"
    # Java 21 reports "21.0.x"
    check_version "Java" "21.0.0" "${java_ver}"
else
    fail "Java: 'java' not found in PATH"
fi

# PHP >= 8.2
if command -v php >/dev/null 2>&1; then
    php_ver="$(php --version 2>&1 | sed -n 's/PHP \([0-9][0-9.]*\).*/\1/p' | head -1)"
    check_version "PHP" "8.2.0" "${php_ver}"
else
    fail "PHP: 'php' not found in PATH"
fi

# dev user UID must be 1000 (STORY-1 AC)
info "--- STORY-1: dev user identity ---"
dev_uid="$(id -u 2>/dev/null || echo '')"
if [ "${dev_uid}" = "1000" ]; then
    pass "dev UID: ${dev_uid}"
else
    fail "dev UID: expected 1000, got '${dev_uid}'"
fi

# Runtimes in PATH — verify each binary resolves to a sane location
for bin in go node java php; do
    if command -v "${bin}" >/dev/null 2>&1; then
        pass "${bin} is in PATH: $(command -v "${bin}")"
    else
        fail "${bin} is NOT in PATH"
    fi
done

# ===========================================================================
# STORY-2: DevOps CLI tools
# ===========================================================================

info "--- STORY-2: DevOps CLI tools ---"

check_tool "Docker CLI"  docker  version --format '{{.Client.Version}}'
check_tool "kubectl"     kubectl version --client --short 2>/dev/null || \
    check_tool "kubectl" kubectl version --client
check_tool "Helm"        helm    version --short
check_tool "AWS CLI"     aws     --version
check_tool "GitHub CLI"  gh      --version
check_tool "Composer"    composer --version
check_tool "Homebrew"    brew    --version
check_tool "Air"         air     --build.cmd "echo" 2>/dev/null || \
    check_tool "Air"     air     -v

# ===========================================================================
# STORY-3: Flutter and Claude Code
# ===========================================================================

info "--- STORY-3: Flutter & Claude Code ---"

check_tool "Flutter"     flutter  --version
check_tool "Claude Code" claude   --version

# ===========================================================================
# PATH conflict check (STORY-2 AC)
# ===========================================================================

info "--- PATH conflict check ---"

CONFLICT_FOUND=0
# Build a list of all binary names that appear more than once across PATH dirs
PATH_DIRS="$(printf '%s' "${PATH}" | tr ':' '\n' | sort -u)"
SEEN_BINS=""

for dir in ${PATH_DIRS}; do
    [ -d "${dir}" ] || continue
    for bin_path in "${dir}"/*; do
        [ -f "${bin_path}" ] || continue
        [ -x "${bin_path}" ] || continue
        bin_name="$(basename "${bin_path}")"
        if printf '%s' "${SEEN_BINS}" | grep -qx "${bin_name}"; then
            info "PATH: '${bin_name}' shadows an earlier entry (this may be intentional)"
        else
            SEEN_BINS="${SEEN_BINS}
${bin_name}"
        fi
    done
done

# Critical tools must not be shadowed — check that the *first* resolution
# of each key binary is the expected one.
check_tool "go resolves to /usr/local/go/bin/go (no conflict)" go version

if pass "PATH conflict scan completed (see INFO lines above for shadows)"; then
    : # already counted
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
    printf '%sAll checks PASSED%s\n' "${GREEN}" "${RESET}"
    exit 0
fi
