#!/usr/bin/env bash

# Reusable functions for shell scripts

# Validates that one or more external dependencies (commands) are available in the PATH.
#
# Usage:
#   validate_dependencies "dep1" "dep2" "dep3"
#
function validate_dependencies() {
    local missing_deps=()
    for dep in "$@"; do
        if ! command -v "${dep}" &> /dev/null; then
            missing_deps+=("${dep}")
        fi
    done

    if (( ${#missing_deps[@]} > 0 )); then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "Please install them and try again." >&2
        exit 1
    fi
}

# --- Logging Functions ---
# Usage:
#   export LOG_LEVEL=DEBUG
#   log_debug "This is a debug message"
#
# LOG_LEVEL can be one of: DEBUG, VERBOSE, INFO, ERROR

# Color constants
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

function log_debug() {
    if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
        echo -e "${GREEN}[DEBUG]${NC} $1" >&2
    fi
}

function log_verbose() {
    if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" || "${LOG_LEVEL:-INFO}" == "VERBOSE" ]]; then
        echo -e "${YELLOW}[VERBOSE]${NC} $1" >&2
    fi
}

function log_info() {
    echo "$1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}
