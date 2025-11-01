#!/bin/bash
set -euo pipefail

# --- jira-create.sh ---
# A script to create Jira tickets with various options and validate required fields.
#
# Usage:
#   ./jira-create.sh [--debug|--verbose|--quiet] <subcommand> [options]
#
# Subcommands:
#   create-minimal <PROJECT> <SUMMARY> <DESCRIPTION> [--type <TYPE>] [--skip-validation]
#   create-from-template <PROJECT> <YAML_FILE> [--skip-validation]
#   fetch-metadata <PROJECT> <ISSUE_TYPE> [--refresh]
#   show-required <PROJECT> <ISSUE_TYPE>
#   generate-template <PROJECT> <ISSUE_TYPE> <OUTPUT_FILE> [--required-only] [--filter <string>] [--add-to-existing]
# --------------------------------------------------

# Source the reusable functions
# shellcheck source=functions.sh
source "$(dirname "$0")/functions.sh"

# shellcheck source=functions-jira.sh
source "$(dirname "$0")/functions-jira.sh"

# --- Configuration ---
# Cache directory for metadata
CACHE_DIR="${HOME}/.jira-cache"

# --- Helper Functions ---

# Get cache file path for a project and issue type
get_cache_file() {
    local project="$1"
    local issue_type="$2"
    echo "${CACHE_DIR}/${project}-${issue_type}.json"
}

# Fetch create metadata from Jira for a specific project and issue type
fetch_metadata_from_jira() {
    local project="$1"
    local issue_type="$2"

    log_verbose "Fetching create metadata for project ${project}, issue type ${issue_type}..."

    local api_endpoint="/rest/api/2/issue/createmeta"
    api_endpoint="${api_endpoint}?projectKeys=${project}&issuetypeNames=${issue_type}&expand=projects.issuetypes.fields"

    # Make the API call using common function
    if ! jira_api_get "${api_endpoint}"; then
        return 1
    fi

    if [ -z "${jira_response_body}" ]; then
        log_error "Received empty response from Jira."
        return 1
    fi

    echo "${jira_response_body}"
}

# Cache metadata to file
cache_metadata() {
    local project="$1"
    local issue_type="$2"
    local metadata="$3"

    local cache_file
    cache_file=$(get_cache_file "${project}" "${issue_type}")

    # Create cache directory if it doesn't exist
    if [ ! -d "${CACHE_DIR}" ]; then
        if ! mkdir -p "${CACHE_DIR}"; then
            log_error "Failed to create cache directory: ${CACHE_DIR}"
            return 1
        fi
        log_debug "Created cache directory: ${CACHE_DIR}"
    fi

    # Write metadata to cache file
    if ! echo "${metadata}" > "${cache_file}"; then
        log_error "Failed to write metadata to cache file: ${cache_file}"
        return 1
    fi

    log_info "Metadata cached to: ${cache_file}"
    return 0
}

# Get cached metadata or fetch if not available
get_metadata() {
    local project="$1"
    local issue_type="$2"
    local force_refresh="${3:-false}"

    local cache_file
    cache_file=$(get_cache_file "${project}" "${issue_type}")

    # If force refresh or cache doesn't exist, fetch from Jira
    if [ "${force_refresh}" = "true" ] || [ ! -f "${cache_file}" ]; then
        log_debug "Fetching metadata from Jira..."
        local metadata
        if ! metadata=$(fetch_metadata_from_jira "${project}" "${issue_type}"); then
            return 1
        fi

        cache_metadata "${project}" "${issue_type}" "${metadata}"
        echo "${metadata}"
    else
        log_debug "Using cached metadata from: ${cache_file}"
        cat "${cache_file}"
    fi
}

# Extract required fields from metadata
get_required_fields() {
    local metadata="$1"

    # Extract fields that are required
    echo "${metadata}" | jq -r '
        .projects[0].issuetypes[0].fields
        | to_entries[]
        | select(.value.required == true)
        | {key: .key, name: .value.name, schema: .value.schema.type, allowedValues: .value.allowedValues}
    '
}

# Validate that all required fields are present in the payload
validate_required_fields() {
    local project="$1"
    local issue_type="$2"
    local payload="$3"

    log_debug "Validating required fields..."

    local metadata
    if ! metadata=$(get_metadata "${project}" "${issue_type}"); then
        log_error "Failed to get metadata for validation."
        return 1
    fi

    local required_fields
    required_fields=$(get_required_fields "${metadata}")

    if [ -z "${required_fields}" ]; then
        log_debug "No required fields found or unable to parse metadata."
        return 0
    fi

    local missing_fields=()

    while IFS= read -r field_json; do
        local field_key
        field_key=$(echo "${field_json}" | jq -r '.key')

        local field_name
        field_name=$(echo "${field_json}" | jq -r '.name')

        # Check if the field exists in the payload
        if ! echo "${payload}" | jq -e ".fields.${field_key}" > /dev/null 2>&1; then
            missing_fields+=("${field_key} (${field_name})")
            log_debug "Missing required field: ${field_key}"
        fi
    done <<< "$(echo "${required_fields}" | jq -c '.')"

    if [ "${#missing_fields[@]}" -gt 0 ]; then
        log_error "Missing required fields:"
        for field in "${missing_fields[@]}"; do
            log_error "  - ${field}"
        done
        return 1
    fi

    log_debug "All required fields are present."
    return 0
}

usage() {
    cat <<EOF
A script to create Jira tickets with various options.

Usage:
  ./jira-create.sh [global-options] <subcommand> [options]

Global Options:
  --help                Show this help message.
  --log-level <LEVEL>   Set log level: DEBUG, VERBOSE, INFO, ERROR (default: INFO).
  --debug               Shortcut for --log-level DEBUG (most verbose).
  --verbose             Shortcut for --log-level VERBOSE.
  --quiet               Shortcut for --log-level ERROR (only errors).

Subcommands:
  create-minimal       Create a minimal Jira ticket with summary and description.
  create-from-template Create a Jira ticket from a YAML template file.
  fetch-metadata       Fetch and cache required fields metadata for a project/issue type.
  show-required        Show required fields for a project/issue type.
  generate-template    Generate a YAML template with all available fields.

'create-minimal' Subcommand Usage:
  ./jira-create.sh create-minimal <PROJECT> <SUMMARY> <DESCRIPTION> [--type <TYPE>] [--skip-validation]

  <PROJECT>           The Jira project key (e.g., PROJ).
  <SUMMARY>           The ticket summary/title.
  <DESCRIPTION>       The ticket description.
  --type <TYPE>       Optional issue type (default: Task). Common values: Task, Bug, Story, Epic.
  --skip-validation   Skip validation of required fields before creation.

'create-from-template' Subcommand Usage:
  ./jira-create.sh create-from-template <PROJECT> <YAML_FILE> [--skip-validation]

  <PROJECT>           The Jira project key (e.g., PROJ).
  <YAML_FILE>         Path to the YAML file with the ticket fields.
                      The template should have 'summary', 'description', 'issuetype', and other fields.
  --skip-validation   Skip validation of required fields before creation.

'fetch-metadata' Subcommand Usage:
  ./jira-create.sh fetch-metadata <PROJECT> <ISSUE_TYPE> [--refresh]

  <PROJECT>           The Jira project key (e.g., PROJ).
  <ISSUE_TYPE>        The issue type (e.g., Task, Bug, Story).
  --refresh           Force refresh the cache even if it exists.

'show-required' Subcommand Usage:
  ./jira-create.sh show-required <PROJECT> <ISSUE_TYPE>

  <PROJECT>           The Jira project key (e.g., PROJ).
  <ISSUE_TYPE>        The issue type (e.g., Task, Bug, Story).

'generate-template' Subcommand Usage:
  ./jira-create.sh generate-template <PROJECT> <ISSUE_TYPE> <OUTPUT_FILE> [options]

  <PROJECT>           The Jira project key (e.g., PROJ).
  <ISSUE_TYPE>        The issue type (e.g., Task, Bug, Story).
  <OUTPUT_FILE>       Path where the YAML template should be created.

  Options:
    --required-only     Only include required fields (default: include all fields).
    --filter <string>   Filter fields by name (case-insensitive partial match).
    --add-to-existing   Add missing fields to an existing template instead of failing.
EOF
}

# --- Subcommands ---

create_minimal() {
    if [ "$#" -lt 3 ]; then
        log_error "Usage: ./jira-create.sh create-minimal <PROJECT> <SUMMARY> <DESCRIPTION> [--type <TYPE>] [--skip-validation]"
        exit 1
    fi

    local project="$1"
    local summary="$2"
    local description="$3"
    shift 3

    local issue_type="Task"
    local skip_validation="false"

    # Parse optional arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --type)
                if [ -z "$2" ]; then
                    log_error "Error: --type requires a value."
                    return 1
                fi
                issue_type="$2"
                shift 2
                ;;
            --skip-validation)
                skip_validation="true"
                shift
                ;;
            *)
                log_error "Error: Unknown option '$1'"
                echo "Usage: ./jira-create.sh create-minimal <PROJECT> <SUMMARY> <DESCRIPTION> [--type <TYPE>] [--skip-validation]"
                return 1
                ;;
        esac
    done

    log_info "Creating minimal ${issue_type} in project ${project}..."
    log_verbose "Summary: ${summary}"
    log_verbose "Description: ${description}"

    # Build JSON payload
    local json_payload
    json_payload=$(jq -n \
        --arg project "${project}" \
        --arg summary "${summary}" \
        --arg description "${description}" \
        --arg issuetype "${issue_type}" \
        '{
            fields: {
                project: {
                    key: $project
                },
                summary: $summary,
                description: $description,
                issuetype: {
                    name: $issuetype
                }
            }
        }')

    log_debug "JSON payload created."
    log_debug "Payload: ${json_payload}"

    # Validate required fields unless skipped
    if [ "${skip_validation}" = "false" ]; then
        if ! validate_required_fields "${project}" "${issue_type}" "${json_payload}"; then
            log_error "Validation failed. Use --skip-validation to bypass, or fetch metadata with:"
            log_error "  ./jira-create.sh show-required ${project} ${issue_type}"
            exit 1
        fi
    else
        log_info "Skipping validation as requested."
    fi

    # Make the API call using common function
    if ! jira_api_post "/rest/api/2/issue" "${json_payload}"; then
        exit 1
    fi

    # Extract ticket key from response
    local ticket_key
    ticket_key=$(echo "${jira_response_body}" | jq -r '.key')
    log_info "Successfully created ticket ${ticket_key}!"
    log_info "View it here: ${jira_base_url}/browse/${ticket_key}"
}

create_from_template() {
    if [ "$#" -lt 2 ]; then
        log_error "Usage: ./jira-create.sh create-from-template <PROJECT> <YAML_FILE> [--skip-validation]"
        exit 1
    fi

    local project="$1"
    local yaml_file="$2"
    shift 2

    local skip_validation="false"

    # Parse optional arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --skip-validation)
                skip_validation="true"
                shift
                ;;
            *)
                log_error "Error: Unknown option '$1'"
                echo "Usage: ./jira-create.sh create-from-template <PROJECT> <YAML_FILE> [--skip-validation]"
                return 1
                ;;
        esac
    done

    log_info "Creating ticket in project ${project} from template ${yaml_file}."

    # Validate YAML file using common function
    if ! validate_yaml_file "${yaml_file}"; then
        exit 1
    fi

    # Read the YAML payload from the file and convert to JSON
    local yaml_content
    yaml_content=$(yq -o=json '.' "${yaml_file}")
    log_debug "Read and converted YAML payload from file."

    # Build the final JSON payload with project key
    local json_payload
    json_payload=$(echo "${yaml_content}" | jq --arg project "${project}" '.fields.project = {key: $project}')
    log_debug "JSON payload created with project key."
    log_debug "Payload: ${json_payload}"

    # Extract issue type from the payload for validation
    local issue_type
    issue_type=$(echo "${json_payload}" | jq -r '.fields.issuetype.name // "Task"')

    # Validate required fields unless skipped
    if [ "${skip_validation}" = "false" ]; then
        if ! validate_required_fields "${project}" "${issue_type}" "${json_payload}"; then
            log_error "Validation failed. Use --skip-validation to bypass, or fetch metadata with:"
            log_error "  ./jira-create.sh show-required ${project} ${issue_type}"
            exit 1
        fi
    else
        log_info "Skipping validation as requested."
    fi

    log_verbose "Creating ticket in project: ${project}"
    log_verbose "Using template file: ${yaml_file}"

    # Make the API call using common function
    if ! jira_api_post "/rest/api/2/issue" "${json_payload}"; then
        exit 1
    fi

    # Extract ticket key from response
    local ticket_key
    ticket_key=$(echo "${jira_response_body}" | jq -r '.key')
    log_info "Successfully created ticket ${ticket_key}!"
    log_info "View it here: ${jira_base_url}/browse/${ticket_key}"
}

fetch_metadata() {
    if [ "$#" -lt 2 ]; then
        log_error "Usage: ./jira-create.sh fetch-metadata <PROJECT> <ISSUE_TYPE> [--refresh]"
        exit 1
    fi

    local project="$1"
    local issue_type="$2"
    shift 2

    local force_refresh="false"

    # Parse optional arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --refresh)
                force_refresh="true"
                shift
                ;;
            *)
                log_error "Error: Unknown option '$1'"
                echo "Usage: ./jira-create.sh fetch-metadata <PROJECT> <ISSUE_TYPE> [--refresh]"
                return 1
                ;;
        esac
    done

    log_info "Fetching metadata for project ${project}, issue type ${issue_type}..."

    local metadata
    if ! metadata=$(get_metadata "${project}" "${issue_type}" "${force_refresh}"); then
        log_error "Failed to fetch metadata."
        exit 1
    fi

    local cache_file
    cache_file=$(get_cache_file "${project}" "${issue_type}")

    log_info "Metadata successfully cached."
    log_info "Cache location: ${cache_file}"
    log_info "Use 'show-required' to view required fields."
}

show_required() {
    if [ "$#" -ne 2 ]; then
        log_error "Usage: ./jira-create.sh show-required <PROJECT> <ISSUE_TYPE>"
        exit 1
    fi

    local project="$1"
    local issue_type="$2"

    log_info "Required fields for project ${project}, issue type ${issue_type}:"
    echo ""

    local metadata
    if ! metadata=$(get_metadata "${project}" "${issue_type}"); then
        log_error "Failed to get metadata. Try fetching it first:"
        log_error "  ./jira-create.sh fetch-metadata ${project} ${issue_type}"
        exit 1
    fi

    local required_fields
    required_fields=$(get_required_fields "${metadata}")

    if [ -z "${required_fields}" ]; then
        log_info "No required fields found (or only standard fields required)."
        return 0
    fi

    # Display required fields in a readable format
    echo "${required_fields}" | jq -r '
        "Field Key:    \(.key)",
        "Field Name:   \(.name)",
        "Field Type:   \(.schema)",
        (if .allowedValues and (.allowedValues | length > 0) then
            "Allowed Values: \(.allowedValues | map(.name) | join(", "))"
        else
            ""
        end),
        "---"
    '
}

generate_template() {
    if [ "$#" -lt 3 ]; then
        log_error "Usage: ./jira-create.sh generate-template <PROJECT> <ISSUE_TYPE> <OUTPUT_FILE> [options]"
        exit 1
    fi

    local project="$1"
    local issue_type="$2"
    local output_file="$3"
    shift 3

    local required_only="false"
    local filter_name=""
    local add_to_existing="false"

    # Parse optional arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --required-only)
                required_only="true"
                shift
                ;;
            --filter)
                if [ -z "$2" ]; then
                    log_error "Error: --filter requires a value."
                    return 1
                fi
                filter_name="$2"
                shift 2
                ;;
            --add-to-existing)
                add_to_existing="true"
                shift
                ;;
            *)
                log_error "Error: Unknown option '$1'"
                echo "Usage: ./jira-create.sh generate-template <PROJECT> <ISSUE_TYPE> <OUTPUT_FILE> [options]"
                return 1
                ;;
        esac
    done

    log_info "Generating template for project ${project}, issue type ${issue_type}..."

    if [ -n "${filter_name}" ]; then
        log_info "Filtering fields by name (case-insensitive): '${filter_name}'"
    fi

    # Check if output file already exists
    local is_updating="false"
    if [ -f "${output_file}" ]; then
        if [ "${add_to_existing}" = "true" ]; then
            log_info "Will add missing fields to existing template '${output_file}'"
            is_updating="true"
        else
            log_error "Output file already exists: ${output_file}"
            log_error "Use --add-to-existing to update it, or choose a different name."
            exit 1
        fi
    fi

    local metadata
    if ! metadata=$(get_metadata "${project}" "${issue_type}"); then
        log_error "Failed to get metadata. Try fetching it first:"
        log_error "  ./jira-create.sh fetch-metadata ${project} ${issue_type}"
        exit 1
    fi

    # Extract all fields or only required fields, with optional name filtering
    local fields_json
    local jq_filter_clause=""

    # Build the jq filter clause for name filtering
    if [ -n "${filter_name}" ]; then
        jq_filter_clause='| select(.value.name | test($filter; "i"))'
    fi

    if [ "${required_only}" = "true" ]; then
        log_verbose "Including only required fields..."
        if [ -n "${filter_name}" ]; then
            fields_json=$(echo "${metadata}" | jq -c --arg filter "${filter_name}" '
                .projects[0].issuetypes[0].fields
                | to_entries[]
                | select(.value.required == true)
                | select(.value.name | test($filter; "i"))
                | {key: .key, name: .value.name, schema: .value.schema.type, required: .value.required, allowedValues: .value.allowedValues}
            ')
        else
            fields_json=$(echo "${metadata}" | jq -c '
                .projects[0].issuetypes[0].fields
                | to_entries[]
                | select(.value.required == true)
                | {key: .key, name: .value.name, schema: .value.schema.type, required: .value.required, allowedValues: .value.allowedValues}
            ')
        fi
    else
        log_verbose "Including all available fields..."
        if [ -n "${filter_name}" ]; then
            fields_json=$(echo "${metadata}" | jq -c --arg filter "${filter_name}" '
                .projects[0].issuetypes[0].fields
                | to_entries[]
                | select(.value.name | test($filter; "i"))
                | {key: .key, name: .value.name, schema: .value.schema.type, required: .value.required, allowedValues: .value.allowedValues}
            ')
        else
            fields_json=$(echo "${metadata}" | jq -c '
                .projects[0].issuetypes[0].fields
                | to_entries[]
                | {key: .key, name: .value.name, schema: .value.schema.type, required: .value.required, allowedValues: .value.allowedValues}
            ')
        fi
    fi

    if [ -z "${fields_json}" ]; then
        log_error "No fields found matching the criteria."
        exit 1
    fi

    # Get existing fields if updating
    local existing_fields=""
    if [ "${is_updating}" = "true" ]; then
        log_debug "Reading existing fields from ${output_file}..."
        if ! existing_fields=$(yq '.fields | keys' "${output_file}" 2>/dev/null); then
            log_error "Failed to read existing fields from ${output_file}"
            log_error "The file may not be a valid YAML template."
            exit 1
        fi
        log_debug "Existing fields: ${existing_fields}"
    else
        # Initialize the YAML file
        echo "# YAML template for creating ${issue_type} in project ${project}" > "${output_file}"
        echo "# Generated by jira-create.sh" >> "${output_file}"
        echo "" >> "${output_file}"
        echo "fields:" >> "${output_file}"
    fi

    local fields_added=0

    # Process each field and add to YAML
    while IFS= read -r field_json; do
        local field_key
        field_key=$(echo "${field_json}" | jq -r '.key')

        # If updating, check if field already exists
        if [ "${is_updating}" = "true" ]; then
            if echo "${existing_fields}" | grep -q "\"${field_key}\""; then
                log_debug "Field '${field_key}' already exists in template. Skipping."
                continue
            fi
        fi

        local field_name
        field_name=$(echo "${field_json}" | jq -r '.name')

        local schema_type
        schema_type=$(echo "${field_json}" | jq -r '.schema // "string"')

        local is_required
        is_required=$(echo "${field_json}" | jq -r '.required // false')

        # Determine a sensible default value based on schema type
        local default_value
        case "${schema_type}" in
            string)
                default_value="'TODO: Enter ${field_name}'"
                ;;
            number)
                default_value="0"
                ;;
            array)
                default_value="[]"
                ;;
            option)
                # Check if there are allowed values
                local allowed_values
                allowed_values=$(echo "${field_json}" | jq -r '.allowedValues // [] | map(.name) | join(", ")')
                if [ -n "${allowed_values}" ] && [ "${allowed_values}" != "" ]; then
                    default_value="{name: 'TODO: Choose from: ${allowed_values}'}"
                else
                    default_value="{name: 'TODO'}"
                fi
                ;;
            user)
                default_value="{name: 'username'}"
                ;;
            priority)
                default_value="{name: 'Medium'}"
                ;;
            project)
                # Skip project field as it's set by the script
                continue
                ;;
            issuetype)
                # Set the issue type to the one specified
                default_value="{name: '${issue_type}'}"
                ;;
            date | datetime)
                default_value="'TODO: YYYY-MM-DD or YYYY-MM-DDTHH:mm:ss.sssZ'"
                ;;
            *)
                default_value="'TODO'"
                ;;
        esac

        # Build comment with field information
        local comment="${field_name}"
        if [ "${is_required}" = "true" ]; then
            comment="${comment} [REQUIRED]"
        fi
        comment="${comment} - Type: ${schema_type}"

        # Add allowed values to comment if available
        local allowed_values
        allowed_values=$(echo "${field_json}" | jq -r 'if .allowedValues and (.allowedValues | length > 0) then .allowedValues | map(.name) | join(", ") else "" end')
        if [ -n "${allowed_values}" ] && [ "${allowed_values}" != "" ]; then
            comment="${comment} - Allowed: ${allowed_values}"
        fi

        # Write the field to YAML with comment (or use yq for updating existing files)
        if [ "${is_updating}" = "true" ]; then
            # Use yq to add field to existing YAML
            # Pass the value via environment variable to avoid shell quoting issues
            log_debug "Adding field '${field_key}' to template..."
            if ! env DEFAULT_VALUE="${default_value}" yq -i ".fields.${field_key} line_comment=\"${comment}\" | .fields.${field_key} = env(DEFAULT_VALUE)" "${output_file}"; then
                log_error "Failed to add field '${field_key}' to template."
            else
                log_verbose "Added field '${field_key}' (${field_name}) to template."
                fields_added=$((fields_added + 1))
            fi
        else
            # Append to new file
            echo "" >> "${output_file}"
            echo "  # ${comment}" >> "${output_file}"
            echo "  ${field_key}: ${default_value}" >> "${output_file}"
            fields_added=$((fields_added + 1))
        fi
    done <<< "${fields_json}"

    if [ "${fields_added}" -gt 0 ]; then
        if [ "${is_updating}" = "true" ]; then
            log_info "Successfully added ${fields_added} field(s) to existing template."
        else
            log_info "Successfully generated template with ${fields_added} field(s)."
        fi
        log_info "Template saved to: ${output_file}"
        log_info ""
        log_info "Next steps:"
        log_info "  1. Edit the template file and fill in the TODO values"
        log_info "  2. Create a ticket with: ./jira-create.sh create-from-template ${project} ${output_file}"
    else
        if [ "${is_updating}" = "true" ]; then
            log_info "No new fields were added to the template."
            log_info "All matching fields already exist in: ${output_file}"
        else
            log_error "No fields were added to the template."
            rm -f "${output_file}"
            exit 1
        fi
    fi
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
        create-minimal)
            create_minimal "$@"
            ;;
        create-from-template)
            create_from_template "$@"
            ;;
        fetch-metadata)
            fetch_metadata "$@"
            ;;
        show-required)
            show_required "$@"
            ;;
        generate-template)
            generate_template "$@"
            ;;
        *)
            echo "Error: Unknown subcommand '$subcommand'"
            usage
            exit 1
            ;;
    esac
}

main "$@"
