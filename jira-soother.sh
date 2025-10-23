#!/bin/bash
set -euo pipefail

# --- jira-soother.sh ---
# A script to interact with Jira for finding fields and applying templates to tickets.
#
# Usage:
#   ./jira-soother.sh find-fields [--filter <string>] [--add-to-template <yaml-file>]
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

usage() {
    cat <<EOF
A script to interact with Jira for finding fields and applying templates to tickets.

Usage:
  ./jira-soother.sh <subcommand> [options]

Subcommands:
  find-fields       Find Jira fields, with optional filtering.
  apply-template    Apply a YAML template to a Jira ticket.

Options:
  --help            Show this help message.

'find-fields' Subcommand Usage:
  ./jira-soother.sh find-fields [--filter <string>] [--add-to-template <yaml-file>]

  --filter <string>           Case-insensitively filter fields by name (partial match).
  --add-to-template <yaml-file> Add the found fields to a YAML template file.
                              If the file doesn't exist, it will be created.
                              Sensible defaults are added for new fields.

'apply-template' Subcommand Usage:
  ./jira-soother.sh apply-template <TICKET_KEY> <YAML_FILE>

  <TICKET_KEY>      The key of the Jira ticket (e.g., PROJ-123).
  <YAML_FILE>       Path to the YAML file with the fields to update.
EOF
}

# --- Subcommands ---

find_fields() {
    local filter_name=""
    local add_to_template_file=""

    # Parse arguments for find_fields
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --add-to-template)
                if [ -z "$2" ]; then
                    log_error "Error: --add-to-template requires a file path."
                    return 1
                fi
                add_to_template_file="$2"
                shift 2
                ;;
            --filter)
                if [ -z "$2" ]; then
                    log_error "Error: --filter requires a value."
                    return 1
                fi
                filter_name="$2"
                shift 2
                ;;
            *)
                log_error "Error: Unknown option '$1'"
                echo "Usage: ./jira-soother.sh find-fields [--filter <string>] [--add-to-template <yaml-file>]"
                return 1
                ;;
        esac
    done

    if [ -n "${filter_name}" ]; then
        log_info "Filtering fields by name (case-insensitive): '${filter_name}'"
    fi

    if [ -n "${add_to_template_file}" ]; then
        log_info "Will add missing fields to '${add_to_template_file}'"
        # Create the file with a 'fields:' key if it doesn't exist
        if [ ! -f "${add_to_template_file}" ]; then
            if ! echo "fields:" > "${add_to_template_file}"; then
                log_error "Could not create template file '${add_to_template_file}'"
                return 1
            fi
        fi
    fi

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
    local jq_query
    jq_query='
        .[]
        | {id, name, schema: (.schema.type // "none"), items: (.schema.items // "none"), allowedValues: (if .allowedValues then [.allowedValues[].name] else [] end) }
    '

    local fields_json
    if [ -n "${filter_name}" ]; then
        jq_query='
            .[]
            | select(.name | test($filter; "i"))
            | {id, name, schema: (.schema.type // "none"), items: (.schema.items // "none"), allowedValues: (if .allowedValues then [.allowedValues[].name] else [] end) }
        '
        fields_json=$(jq --arg filter "${filter_name}" "${jq_query}" <<< "${body}")
    else
        fields_json=$(jq "${jq_query}" <<< "${body}")
    fi

    if [ -z "${fields_json}" ]; then
        log_info "No fields found matching the criteria."
        return 0
    fi

    # If --add-to-template is not used, just print the fields and exit
    if [ -z "${add_to_template_file}" ]; then
        echo "${fields_json}"
        return 0
    fi

    # Add fields to the template file
    local existing_fields
    existing_fields=$(yq '.fields | keys' "${add_to_template_file}")

    local fields_added_count=0
    # Read each JSON object from the stream
    while IFS= read -r field_json; do
        local field_id
        field_id=$(echo "${field_json}" | jq -r '.id')

        # Check if the field is already in the template
        if echo "${existing_fields}" | grep -q "${field_id}"; then
            log_debug "Field '${field_id}' already exists in template. Skipping."
            continue
        fi

        local schema_type
        schema_type=$(echo "${field_json}" | jq -r '.schema')
        local default_value

        # Determine a sensible default value based on schema
        case "${schema_type}" in
            string)
                default_value="''" # Empty string
                ;;
            number)
                default_value="0"
                ;;
            array)
                default_value="[]" # Empty array
                ;;
            option)
                default_value='{"name": "TODO"}' # Object with name property
                ;;
            user)
                default_value='{"name": "username"}'
                ;;
            priority)
                default_value='{"name": "Medium"}'
                ;;
            *)
                default_value="'TODO'" # Default for unknown types
                ;;
        esac

        local field_name
        field_name=$(echo "${field_json}" | jq -r '.name')
        local comment
        comment="${field_name}: A field of type '${schema_type}'."

        # Add the field to the YAML file with a comment
        # The yq syntax is tricky. We are setting a line comment, then piping that to another yq expression
        # that sets the value. The value is passed as an environment variable to yq to avoid shell quoting issues.
        if ! env DEFAULT_VALUE="${default_value}" yq -i ".fields.${field_id} line_comment=\"${comment}\" | .fields.${field_id} = env(DEFAULT_VALUE)" "${add_to_template_file}"; then
            log_error "Failed to add field '${field_id}' to '${add_to_template_file}'"
        else
            log_info "Added field '${field_id}' to '${add_to_template_file}'"
            fields_added_count=$((fields_added_count + 1))
        fi
    done <<< "$(echo "${fields_json}" | jq -c '.')"

    if [ "${fields_added_count}" -gt 0 ]; then
        log_info "Successfully added ${fields_added_count} field(s) to '${add_to_template_file}'."
    else
        log_info "No new fields were added to '${add_to_template_file}'."
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

    if [ "$#" -eq 0 ] || [[ " $* " == *" --help "* ]]; then
        usage
        exit 0
    fi

    local subcommand="$1"
    shift

    case "$subcommand" in
        find-fields)
            find_fields "$@"
            ;;
        apply-template)
            apply_template "$@"
            ;;
        *)
            echo "Error: Unknown subcommand '$subcommand'"
            usage
            exit 1
            ;;
    esac
}

main "$@"
