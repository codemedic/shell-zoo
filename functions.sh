#!/usr/bin/env bash

# functions.sh - Reusable utility functions for shell scripts
# -----------------------------------------------------------------------------
# Description:
#   Common utility functions including dependency validation and leveled
#   logging (DEBUG, VERBOSE, INFO, WARNING, ERROR) with color support.
#   This library is sourced by other scripts to provide consistent logging
#   and validation capabilities.
#
# Requirements:
#   - Bash 4.0+
#
# Usage:
#   source "$(dirname "$0")/functions.sh"
#   validate_dependencies "jq" "curl"
#   log_info "Starting process..."
#
# Functions:
#   - validate_dependencies: Check for required external commands
#   - log_debug: Debug-level logging (when LOG_LEVEL=DEBUG)
#   - log_verbose: Verbose logging (when LOG_LEVEL=DEBUG or VERBOSE)
#   - log_info: Informational logging (default level)
#   - log_warning: Warning messages
#   - log_error: Error messages (always shown)
#
# Environment Variables:
#   LOG_LEVEL: Set logging verbosity (DEBUG|VERBOSE|INFO|ERROR, default: INFO)
#
# Author: codemedic
# Repository: https://github.com/codemedic/shell-zoo
# Date: November 2025
# -----------------------------------------------------------------------------

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
readonly DARK_GRAY='\033[1;30m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Logging levels
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["VERBOSE"]=1
    ["INFO"]=2
    ["WARNING"]=3
    ["ERROR"]=4
)
# Logging level threshold
LOG_LEVEL="${LOG_LEVEL:-INFO}"
# Logging colours for each level
readonly LOG_COLORS=(
    "${DARK_GRAY}" # DEBUG   = 0
    "${CYAN}"      # VERBOSE = 1
    "${GREEN}"     # INFO    = 2
    "${YELLOW}"    # WARNING = 3
    "${RED}"       # ERROR   = 4
)
# Log line prefixes by level
readonly LOG_PREFIXES=(
    DBG # DEBUG   = 0
    VRB # VERBOSE = 1
    INF # INFO    = 2
    WRN # WARNING = 3
    ERR # ERROR   = 4
)

log() {
    local this_level="${LOG_LEVELS[$1]:-2}"
    shift

    local level_threshold="${LOG_LEVELS[${LOG_LEVEL:-INFO}]:-2}"
    if (( this_level < level_threshold )); then
        return
    fi

    echo -e "${LOG_COLORS[$this_level]}${LOG_PREFIXES[$this_level]}${NC} $*" >&2
}

function log_debug() {
    log DEBUG "$@"
}

function log_verbose() {
    log VERBOSE "$@"
}

function log_info() {
    log INFO "$@"
}

function log_warning() {
    log WARNING "$@"
}

function log_error() {
    log ERROR "$@"
}
