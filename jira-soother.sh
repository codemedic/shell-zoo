#!/bin/bash
set -euo pipefail

# --- jira-soother.sh ---
# A script to interact with Jira for finding fields and applying templates to tickets.
#
# Usage:
#   ./jira-soother.sh find-fields
#   ./jira-soother.sh apply-template <TICKET_KEY> <YAML_FILE>
# --------------------------------------------------

# Source the reusable functions
# shellcheck source=functions.sh
source "$(dirname "$0")/functions.sh"

# --- Configuration ---
# Ensure Jira credentials are present in environment variables. If the variables are not present, bail out.
: "${jira_base_url:?Environment variable jira_base_url not set.}"
: "${jira_user:?Environment variable jira_user not set.}"
: "${jira_password:?Environment variable jira_password not set.}"

# --- Helper Functions ---

# Create Basic Auth header
get_auth_header() {
    local auth_string
    auth_string=$(echo -n "${jira_user}:${jira_password}" | base64)
    echo "Authorization: Basic ${auth_string}"
}

# --- Subcommands ---

find_fields() {
    log_verbose "Fetching fields from ${jira_base_url}..."

    local auth_header
    auth_header=$(get_auth_header)
    log_debug "Auth header created."

    local api_endpoint="${jira_base_url}/rest/api/2/field"
    log_debug "API endpoint: ${api_endpoint}"

    # Make the API call
    local response
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "${auth_header}" "${api_endpoint}")
    log_debug "Curl response received."

    # Separate HTTP status from response body
    local http_status
    http_status=$(echo "${response}" | grep "HTTP_STATUS:" | cut -d: -f2)
    local body
    body=$(echo "${response}" | sed '$d')
    log_debug "HTTP status: ${http_status}"

    # Check for successful response
    if [ "$http_status" -ne 200 ]; then
        log_error "Failed to fetch fields from Jira. HTTP Status: ${http_status}"
        log_error "Response Body:"
        log_error "${body}" | jq .
        exit 1
    fi

    if [ -z "${body}" ]; then
        log_error "Received empty response from Jira."
        exit 1
    fi

    log_debug "Response body is not empty. Parsing with jq..."
    # Use a here-string (<<<) which is more robust for large inputs than echo.
    # Also, handle cases where 'items', 'schema', or 'allowedValues' may be null.
    if ! jq '.[] | {id, name, schema: (.schema.type // "none"), items: (.schema.items // "none"), allowedValues: (if .allowedValues then [.allowedValues[].name] else [] end) }' <<< "${body}"; then
        log_error "jq failed to parse the response. Exit code: $?"
        return 5
    fi
}

apply_template() {
    if [ "$#" -ne 2 ]; then
        log_error "Usage: ./jira-soother.sh apply-template <TICKET_KEY> <YAML_FILE>"
        exit 1
    fi

    local ticket_key="$1"
    local yaml_file="$2"
    log_info "Attempting to apply template to ticket ${ticket_key} with data from ${yaml_file}."

    # Check if the YAML file exists
    if [ ! -f "$yaml_file" ]; then
        log_error "YAML file not found at: ${yaml_file}"
        exit 1
    fi

    # Read the YAML payload from the file and convert to JSON
    local json_payload
    json_payload=$(yq -o=json '.' "$yaml_file")
    log_debug "Read and converted YAML payload from file."

    # Validate if the file content is valid JSON
    if ! echo "${json_payload}" | jq . > /dev/null 2>&1; then
        log_error "The file '${yaml_file}' does not contain valid YAML/JSON."
        exit 1
    fi
    log_debug "JSON payload is valid."

    local auth_header
    auth_header=$(get_auth_header)
    log_debug "Auth header created."

    local api_endpoint="${jira_base_url}/rest/api/2/issue/${ticket_key}"
    log_debug "API endpoint: ${api_endpoint}"

    log_verbose "Updating ticket: ${ticket_key}"
    log_verbose "Using config file: ${yaml_file}"
    log_debug "Payload: ${json_payload}"

    # Make the API call
    local response
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
         -X PUT \
         -H "${auth_header}" \
         -H "Content-Type: application/json" \
         -H "Accept: application/json" \
         --data "${json_payload}" \
         "${api_endpoint}")
    log_debug "Curl response received."

    # Separate HTTP status from response body
    local http_status
    http_status=$(echo "${response}" | grep "HTTP_STATUS:" | cut -d: -f2)
    local body
    body=$(echo "${response}" | sed '$d') # Remove last line (the status)
    log_debug "HTTP status: ${http_status}"

    # Check the result
    if [ "$http_status" -eq 204 ]; then
        log_info "Successfully updated ticket ${ticket_key}!"
        log_info "View it here: ${jira_base_url}/browse/${ticket_key}"
    else
        log_error "Error updating ticket. Status: ${http_status}"
        log_error "Response Body:"
        log_error "${body}" | jq . # Pretty-print the error JSON
    fi
}

# --- Main Logic ---
main() {
    # Validate dependencies
    validate_dependencies "jq" "curl" "base64" "yq"

    if [ "$#" -eq 0 ]; then
        echo "Usage: ./jira-soother.sh <subcommand> [options]"
        echo "Subcommands: find-fields, apply-template"
        exit 1
    fi

    local subcommand="$1"
    shift

    case "$subcommand" in
        find-fields)
            find_fields
            ;;
        apply-template)
            apply_template "$@"
            ;;
        *)
            echo "Error: Unknown subcommand '$subcommand'"
            echo "Usage: ./jira-soother.sh <subcommand> [options]"
            exit 1
            ;;
    esac
}

main "$@"
