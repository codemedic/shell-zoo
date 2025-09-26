#!/usr/bin/env bash

# image-to-data-url.sh - Convert an image file to a data URL
# -----------------------------------------------------------------------------
# Description:
#   This script converts an image file to a base64-encoded data URL that can be 
#   used directly in HTML, CSS, or other web/application content. The script
#   automatically determines the MIME type and validates that the image is
#   small enough to be practically used as a data URL.
#
# Requirements:
#   - file: For MIME type detection
#   - stat: For file size checking
#   - base64: For base64 encoding
#   - Bash 5.1+
#
# Usage:
#   ./image-to-data-url.sh <path_to_image>
#
# Examples:
#   ./image-to-data-url.sh icon.png
#   ./image-to-data-url.sh ~/Pictures/logo.jpg
#   ./image-to-data-url.sh /path/to/favicon.ico
#
# Output:
#   A data URL string in the format: data:<mime-type>;base64,<encoded-data>
#   This can be used directly in:
#   - HTML: <img src="data:image/png;base64,iVBORw0K...">
#   - CSS: background-image: url("data:image/png;base64,iVBORw0K...");
#
# Notes:
#   - The script enforces a maximum file size of 32KB by default
#   - Compatible with both Linux and macOS environments
#   - Validates all dependencies before execution
#   - Returns non-zero exit code on errors
#
# Author: codemedic
# Repository: https://github.com/codemedic/shell-zoo
# Date: September 2025
# -----------------------------------------------------------------------------

set -euo pipefail

# Source reusable functions
# shellcheck source=functions.sh
source "$(dirname "$0")/functions.sh"

# Constants
readonly MAX_FILE_SIZE_KB=32
readonly MAX_FILE_SIZE_BYTES=$((MAX_FILE_SIZE_KB * 1024))

# --- Validation Functions ---

# Validates that a file path was provided.
function validate_input() {
    if [[ -z "$1" ]]; then
        echo "Error: No image file specified." >&2
        echo "Usage: $0 <path_to_image>" >&2
        exit 1
    fi
}

# Validates that the file exists and is not empty.
function validate_file() {
    local file_path="$1"
    if [[ ! -f "${file_path}" ]]; then
        echo "Error: File '${file_path}' not found." >&2
        exit 1
    fi

    if [[ ! -s "${file_path}" ]]; then
        echo "Error: File '${file_path}' is empty." >&2
        exit 1
    fi
}

# Validates that the file size is within the acceptable limit for data URLs.
function validate_file_size() {
    local file_path="$1"
    local file_size
    file_size=$(stat -c%s "${file_path}")

    if (( file_size > MAX_FILE_SIZE_BYTES )); then
        echo "Error: Image file size (${file_size} bytes) exceeds the ${MAX_FILE_SIZE_KB}KB limit." >&2
        echo "Data URLs are not recommended for large files." >&2
        exit 1
    fi
}

# --- Core Functions ---

# Determines the MIME type of the given file.
function get_mime_type() {
    local file_path="$1"
    local mime_type
    mime_type=$(file --brief --mime-type "${file_path}")
    echo "${mime_type}"
}

# Encodes the file content in base64, ensuring it's a single line.
function base64_encode() {
    local file_path="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS base64 command
        base64 -i "${file_path}"
    else
        # GNU/Linux base64 command
        base64 --wrap=0 "${file_path}"
    fi
}

# --- Main Execution ---

function main() {
    # Validate dependencies
    validate_dependencies "file" "stat" "base64"

    local image_path="$1"

    # Validate input and file
    validate_input "${image_path}"
    validate_file "${image_path}"
    validate_file_size "${image_path}"

    # Get MIME type
    local mime_type
    mime_type=$(get_mime_type "${image_path}")

    # Base64 encode the image
    local encoded_data
    encoded_data=$(base64_encode "${image_path}")

    # Construct and print the data URL
    echo "data:${mime_type};base64,${encoded_data}"
}

# Pass all arguments to the main function.
# This makes the script testable and reusable.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
