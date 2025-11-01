#!/bin/bash
set -euo pipefail

# --- jira-soother.sh ---
# A script to interact with Jira for finding fields and applying templates to tickets.
#
# Usage:
#   ./jira-soother.sh [--debug|--verbose|--quiet] <subcommand> [options]
#
# Subcommands:
#   find-fields [--filter <string>] [--add-to-template <yaml-file>]
#   apply-template <TICKET_KEY> <YAML_FILE>
# --------------------------------------------------

# Source the reusable functions
# shellcheck source=functions.sh
source "$(dirname "$0")/functions.sh"

# shellcheck source=functions-jira.sh
source "$(dirname "$0")/functions-jira.sh"

usage() {
    cat <<EOF
A script to interact with Jira for finding fields and applying templates to tickets.

Usage:
  ./jira-soother.sh [global-options] <subcommand> [options]

Global Options:
  --help                Show this help message.
  --log-level <LEVEL>   Set log level: DEBUG, VERBOSE, INFO, ERROR (default: INFO).
  --debug               Shortcut for --log-level DEBUG (most verbose).
  --verbose             Shortcut for --log-level VERBOSE.
  --quiet               Shortcut for --log-level ERROR (only errors).

Subcommands:
  find-fields       Find Jira fields, with optional filtering.
  apply-template    Apply a YAML template to a Jira ticket.

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

    # Make the API call using common function
    if ! jira_api_get "/rest/api/2/field"; then
        exit 1
    fi

    local body="${jira_response_body}"

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

    # Validate YAML file using common function
    if ! validate_yaml_file "${yaml_file}"; then
        exit 1
    fi

    # Read the YAML payload from the file and convert to JSON
    local json_payload
    json_payload=$(yq -o=json '.' "$yaml_file")
    log_debug "Read and converted YAML payload from file."

    log_verbose "Updating ticket: ${ticket_key}"
    log_verbose "Using config file: ${yaml_file}"

    # Make the API call using common function
    if ! jira_api_put "/rest/api/2/issue/${ticket_key}" "${json_payload}"; then
        exit 1
    fi

    log_info "Successfully updated ticket ${ticket_key}!"
    log_info "View it here: ${jira_base_url}/browse/${ticket_key}"
}

# --- Main Logic ---
main() {
    # Set default log level
    export LOG_LEVEL="${LOG_LEVEL:-INFO}"

    # Parse global options first (check for help before validating environment)
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help)
                usage
                exit 0
                ;;
            --log-level)
                if [ -z "$2" ]; then
                    log_error "Error: --log-level requires a value (DEBUG, VERBOSE, INFO, ERROR)."
                    exit 1
                fi
                # Validate log level
                case "$2" in
                    DEBUG|VERBOSE|INFO|ERROR)
                        export LOG_LEVEL="$2"
                        ;;
                    *)
                        log_error "Error: Invalid log level '$2'. Must be one of: DEBUG, VERBOSE, INFO, ERROR."
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --debug)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            --verbose)
                export LOG_LEVEL="VERBOSE"
                shift
                ;;
            --quiet)
                export LOG_LEVEL="ERROR"
                shift
                ;;
            -*)
                # Unknown option, might be for subcommand
                break
                ;;
            *)
                # Not an option, must be the subcommand
                break
                ;;
        esac
    done

    if [ "$#" -eq 0 ]; then
        usage
        exit 0
    fi

    # Validate Jira environment variables (after help check)
    validate_jira_env

    # Validate dependencies
    validate_dependencies "jq" "curl" "base64" "yq"

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
