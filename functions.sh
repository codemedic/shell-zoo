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
