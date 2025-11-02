#!/bin/bash
set -euo pipefail

# --- jira.sh ---
# Unified script for Jira ticket operations, field discovery, and template management.
#
# Usage:
#   ./jira.sh [--debug|--verbose|--quiet] <command> [options]
#
# Commands:
#   create, create-from-template, update
#   list-fields, list-issue-types, show-required
#   generate-template, fetch-metadata
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
Unified script for Jira ticket operations, field discovery, and template management.

Usage:
  ./jira.sh [global-options] <command> [options]

Global Options:
  --help                Show this help message
  --log-level <LEVEL>   Set log level: DEBUG, VERBOSE, INFO, ERROR (default: INFO)
  --debug               Shortcut for --log-level DEBUG (most verbose)
  --verbose             Shortcut for --log-level VERBOSE
  --quiet               Shortcut for --log-level ERROR (only errors)

Commands:

  Issue Operations:
    create <PROJECT> <SUMMARY> <DESCRIPTION> [options]
        Create a minimal ticket with basic fields.
        Options: --type <TYPE>, --skip-validation

    create-from-template <PROJECT> <YAML_FILE> [options]
        Create a ticket from a YAML template.
        Options: --skip-validation, --interactive, --no-interactive

    update <TICKET_KEY> <YAML_FILE> [options]
        Update an existing ticket with a YAML template.
        Options: --interactive, --no-interactive

  Field Discovery:
    list-fields [<PROJECT> <ISSUE_TYPE>] [options]
        List available Jira fields.
        Without PROJECT/ISSUE_TYPE: Lists all global fields (exploration only)
        With PROJECT/ISSUE_TYPE: Lists fields for that specific combination
        Options: --filter <string>

    list-issue-types <PROJECT>
        List available issue types for a project.

    show-required <PROJECT> <ISSUE_TYPE>
        Show required fields for a project/issue type.

  Template Management:
    generate-template <PROJECT> <ISSUE_TYPE> <OUTPUT_FILE> [options]
        Generate a YAML template with available fields.
        Options: --required-fields, --filter <string> (repeatable), --update

  Metadata Management:
    fetch-metadata <PROJECT> <ISSUE_TYPE> [options]
        Fetch and cache field metadata for a project/issue type.
        Options: --refresh

Examples:
  # Create a ticket
  jira.sh create PROJ "Fix login bug" "Users cannot log in" --type Bug

  # Create from interactive template
  jira.sh create-from-template PROJ story-template.yml

  # Update ticket with interactive template
  jira.sh update PROJ-123 update-template.yml

  # List all global fields (for exploration)
  jira.sh list-fields --filter "Story"

  # List fields for specific project/issue type
  jira.sh list-fields PROJ Story

  # List issue types for a project
  jira.sh list-issue-types PROJ

  # Generate template with only required fields
  jira.sh generate-template PROJ Story template.yml --required-fields

  # Generate template with multiple specific fields
  jira.sh generate-template PROJ Story template.yml --filter "Sprint" --filter "Story Points"

  # Show required fields
  jira.sh show-required PROJ Story

For detailed help on any command:
  jira.sh <command> --help

Note: Templates support interactive placeholders:
      - {{PROMPT: text}} and {{INPUT: text}} for single-line input
      - {{PROMPT_MULTI: text}} and {{INPUT_MULTI: text}} for multi-line input
      Multi-line input: type 'END' on a new line when finished

EOF
}

# --- Commands ---

cmd_create() {
    if [ "$#" -lt 3 ]; then
        log_error "Usage: ./jira.sh create <PROJECT> <SUMMARY> <DESCRIPTION> [--type <TYPE>] [--skip-validation]"
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
                echo "Usage: ./jira.sh create <PROJECT> <SUMMARY> <DESCRIPTION> [--type <TYPE>] [--skip-validation]"
                return 1
                ;;
        esac
    done

    log_info "Creating ${issue_type} in project ${project}..."
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
            log_error "Validation failed. Use --skip-validation to bypass, or check required fields with:"
            log_error "  ./jira.sh show-required ${project} ${issue_type}"
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

cmd_create_from_template() {
    if [ "$#" -lt 2 ]; then
        log_error "Usage: ./jira.sh create-from-template <PROJECT> <YAML_FILE> [--skip-validation] [--interactive|--no-interactive]"
        exit 1
    fi

    local project="$1"
    local yaml_file="$2"
    shift 2

    local skip_validation="false"
    local interactive="auto"

    # Parse optional arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --skip-validation)
                skip_validation="true"
                shift
                ;;
            --interactive)
                interactive="true"
                shift
                ;;
            --no-interactive)
                interactive="false"
                shift
                ;;
            *)
                log_error "Error: Unknown option '$1'"
                echo "Usage: ./jira.sh create-from-template <PROJECT> <YAML_FILE> [--skip-validation] [--interactive|--no-interactive]"
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

    # Auto-detect interactive mode if not explicitly set
    if [ "${interactive}" = "auto" ]; then
        # Check if template contains placeholders
        if echo "${json_payload}" | jq -e '.. | select(type == "string" and test("^\\{\\{(PROMPT|INPUT):"))' > /dev/null 2>&1; then
            # Check if we're in an interactive terminal
            if [ -t 0 ]; then
                interactive="true"
                log_verbose "Auto-detected interactive placeholders in template. Enabling interactive mode."
            else
                interactive="false"
                log_error "Template contains interactive placeholders but stdin is not a terminal."
                log_error "Either run in an interactive terminal or use --no-interactive to skip prompts."
                exit 1
            fi
        else
            interactive="false"
        fi
    fi

    # Process interactive placeholders if needed
    if [ "${interactive}" = "true" ]; then
        if ! json_payload=$(process_interactive_template "${json_payload}" "true"); then
            exit 1
        fi
    elif [ "${interactive}" = "false" ]; then
        if ! json_payload=$(process_interactive_template "${json_payload}" "false"); then
            exit 1
        fi
    fi

    log_debug "Final payload: ${json_payload}"

    # Extract issue type from the payload for validation
    local issue_type
    issue_type=$(echo "${json_payload}" | jq -r '.fields.issuetype.name // "Task"')

    # Validate required fields unless skipped
    if [ "${skip_validation}" = "false" ]; then
        if ! validate_required_fields "${project}" "${issue_type}" "${json_payload}"; then
            log_error "Validation failed. Use --skip-validation to bypass, or check required fields with:"
            log_error "  ./jira.sh show-required ${project} ${issue_type}"
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

cmd_update() {
    if [ "$#" -lt 2 ]; then
        log_error "Usage: ./jira.sh update <TICKET_KEY> <YAML_FILE> [--interactive|--no-interactive]"
        exit 1
    fi

    local ticket_key="$1"
    local yaml_file="$2"
    shift 2

    local interactive="auto"

    # Parse optional arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --interactive)
                interactive="true"
                shift
                ;;
            --no-interactive)
                interactive="false"
                shift
                ;;
            *)
                log_error "Error: Unknown option '$1'"
                echo "Usage: ./jira.sh update <TICKET_KEY> <YAML_FILE> [--interactive|--no-interactive]"
                return 1
                ;;
        esac
    done

    log_info "Updating ticket ${ticket_key} with data from ${yaml_file}."

    # Validate YAML file using common function
    if ! validate_yaml_file "${yaml_file}"; then
        exit 1
    fi

    # Read the YAML payload from the file and convert to JSON
    local json_payload
    json_payload=$(yq -o=json '.' "$yaml_file")
    log_debug "Read and converted YAML payload from file."

    # Auto-detect interactive mode if not explicitly set
    if [ "${interactive}" = "auto" ]; then
        # Check if template contains placeholders
        if echo "${json_payload}" | jq -e '.. | select(type == "string" and test("^\\{\\{(PROMPT|INPUT):"))' > /dev/null 2>&1; then
            # Check if we're in an interactive terminal
            if [ -t 0 ]; then
                interactive="true"
                log_verbose "Auto-detected interactive placeholders in template. Enabling interactive mode."
            else
                interactive="false"
                log_error "Template contains interactive placeholders but stdin is not a terminal."
                log_error "Either run in an interactive terminal or use --no-interactive to skip prompts."
                exit 1
            fi
        else
            interactive="false"
        fi
    fi

    # Process interactive placeholders if needed
    if [ "${interactive}" = "true" ]; then
        if ! json_payload=$(process_interactive_template "${json_payload}" "true"); then
            exit 1
        fi
    elif [ "${interactive}" = "false" ]; then
        if ! json_payload=$(process_interactive_template "${json_payload}" "false"); then
            exit 1
        fi
    fi

    log_verbose "Updating ticket: ${ticket_key}"
    log_verbose "Using template file: ${yaml_file}"
    log_debug "Final payload: ${json_payload}"

    # Make the API call using common function
    if ! jira_api_put "/rest/api/2/issue/${ticket_key}" "${json_payload}"; then
        exit 1
    fi

    log_info "Successfully updated ticket ${ticket_key}!"
    log_info "View it here: ${jira_base_url}/browse/${ticket_key}"
}

cmd_list_fields() {
    local project=""
    local issue_type=""
    local filter_name=""

    # Parse positional and optional arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --filter)
                if [ -z "$2" ]; then
                    log_error "Error: --filter requires a value."
                    return 1
                fi
                filter_name="$2"
                shift 2
                ;;
            --help)
                echo "Usage: ./jira.sh list-fields [<PROJECT> <ISSUE_TYPE>] [--filter <string>]"
                echo ""
                echo "List available Jira fields."
                echo ""
                echo "Without PROJECT/ISSUE_TYPE: Lists all global Jira fields (exploration only)"
                echo "With PROJECT/ISSUE_TYPE: Lists fields available for that specific combination"
                echo ""
                echo "Options:"
                echo "  --filter <string>   Filter fields by name (case-insensitive)"
                return 0
                ;;
            -*)
                log_error "Error: Unknown option '$1'"
                echo "Usage: ./jira.sh list-fields [<PROJECT> <ISSUE_TYPE>] [--filter <string>]"
                return 1
                ;;
            *)
                # Positional arguments
                if [ -z "${project}" ]; then
                    project="$1"
                    shift
                elif [ -z "${issue_type}" ]; then
                    issue_type="$1"
                    shift
                else
                    log_error "Error: Too many positional arguments"
                    echo "Usage: ./jira.sh list-fields [<PROJECT> <ISSUE_TYPE>] [--filter <string>]"
                    return 1
                fi
                ;;
        esac
    done

    # Validate that if project is provided, issue_type must also be provided
    if [ -n "${project}" ] && [ -z "${issue_type}" ]; then
        log_error "Error: When PROJECT is specified, ISSUE_TYPE must also be specified"
        echo "Usage: ./jira.sh list-fields [<PROJECT> <ISSUE_TYPE>] [--filter <string>]"
        return 1
    fi

    if [ -n "${filter_name}" ]; then
        log_info "Filtering fields by name (case-insensitive): '${filter_name}'"
    fi

    local fields_json

    # If project and issue type are provided, use metadata (project-specific fields)
    if [ -n "${project}" ] && [ -n "${issue_type}" ]; then
        log_info "Fetching fields for project ${project}, issue type ${issue_type}..."

        local metadata
        if ! metadata=$(get_metadata "${project}" "${issue_type}"); then
            log_error "Failed to get metadata. Try fetching it first:"
            log_error "  ./jira.sh fetch-metadata ${project} ${issue_type}"
            exit 1
        fi

        # Extract fields from metadata
        local jq_query='
            .projects[0].issuetypes[0].fields
            | to_entries[]
            | {id: .key, name: .value.name, schema: (.value.schema.type // "none"), items: (.value.schema.items // "none"), required: .value.required, allowedValues: (if .value.allowedValues then [.value.allowedValues[] | (.name // .value // .id // "" | tostring)] else [] end)}
        '

        if [ -n "${filter_name}" ]; then
            jq_query='
                .projects[0].issuetypes[0].fields
                | to_entries[]
                | select(.value.name | test($filter; "i"))
                | {id: .key, name: .value.name, schema: (.value.schema.type // "none"), items: (.value.schema.items // "none"), required: .value.required, allowedValues: (if .value.allowedValues then [.value.allowedValues[] | (.name // .value // .id // "" | tostring)] else [] end)}
            '
            fields_json=$(jq --arg filter "${filter_name}" "${jq_query}" <<< "${metadata}")
        else
            fields_json=$(jq "${jq_query}" <<< "${metadata}")
        fi
    else
        # No project/issue type - list all global fields
        log_info "Fetching all global Jira fields (for exploration only)..."
        log_verbose "Note: Use 'list-fields <PROJECT> <ISSUE_TYPE>' for project-specific fields"

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
        local jq_query
        jq_query='
            .[]
            | {id, name, schema: (.schema.type // "none"), items: (.schema.items // "none"), allowedValues: (if .allowedValues then [.allowedValues[] | (.name // .value // .id // "" | tostring)] else [] end)}
        '

        if [ -n "${filter_name}" ]; then
            jq_query='
                .[]
                | select(.name | test($filter; "i"))
                | {id, name, schema: (.schema.type // "none"), items: (.schema.items // "none"), allowedValues: (if .allowedValues then [.allowedValues[] | (.name // .value // .id // "" | tostring)] else [] end)}
            '
            fields_json=$(jq --arg filter "${filter_name}" "${jq_query}" <<< "${body}")
        else
            fields_json=$(jq "${jq_query}" <<< "${body}")
        fi
    fi

    if [ -z "${fields_json}" ]; then
        log_info "No fields found matching the criteria."
        return 0
    fi

    # Output the fields
    echo "${fields_json}"
}

cmd_list_issue_types() {
    if [ "$#" -ne 1 ]; then
        log_error "Usage: ./jira.sh list-issue-types <PROJECT>"
        exit 1
    fi

    local project="$1"

    log_info "Fetching issue types for project ${project}..."

    # Call Jira API to get project metadata including issue types
    local api_endpoint="/rest/api/2/issue/createmeta?projectKeys=${project}&expand=projects.issuetypes"

    if ! jira_api_get "${api_endpoint}"; then
        log_error "Failed to fetch issue types for project ${project}"
        exit 1
    fi

    local body="${jira_response_body}"

    if [ -z "${body}" ]; then
        log_error "Received empty response from Jira."
        exit 1
    fi

    # Check if project exists
    local project_count
    project_count=$(echo "${body}" | jq -r '.projects | length')

    if [ "${project_count}" -eq 0 ]; then
        log_error "Project '${project}' not found or you don't have permission to access it."
        exit 1
    fi

    log_info "Available issue types for project ${project}:"
    echo ""

    # Extract issue types with name, id, and description
    # Format: Display the name prominently, and if the name differs from what needs to be used in templates, show both
    echo "${body}" | jq -r '
        .projects[0].issuetypes[]
        | {
            name: .name,
            id: .id,
            description: .description,
            subtask: .subtask
        }
        | if .subtask then
            "  • \(.name) (ID: \(.id)) [SUBTASK]"
          else
            "  • \(.name) (ID: \(.id))"
          end,
          if .description and .description != "" then
            "    Description: \(.description)"
          else
            empty
          end,
          "    Usage in templates: issuetype: {name: '\''\(.name)'\''}"
    '

    echo ""
    log_info "Note: Use the exact name shown above in templates and --type flag."
    log_info "      Names are case-sensitive (e.g., 'Story' not 'story')."
}

cmd_show_required() {
    if [ "$#" -ne 2 ]; then
        log_error "Usage: ./jira.sh show-required <PROJECT> <ISSUE_TYPE>"
        exit 1
    fi

    local project="$1"
    local issue_type="$2"

    log_info "Required fields for project ${project}, issue type ${issue_type}:"
    echo ""

    local metadata
    if ! metadata=$(get_metadata "${project}" "${issue_type}"); then
        log_error "Failed to get metadata. Try fetching it first:"
        log_error "  ./jira.sh fetch-metadata ${project} ${issue_type}"
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
        (if .key == "project" then
            "Note:         Automatically set to \(.allowedValues[0].key // .allowedValues[0].name // .allowedValues[0].value // "")"
        elif .key == "issuetype" then
            "Note:         Automatically set to \(.allowedValues[0].name // .allowedValues[0].value // "")"
        elif .allowedValues and (.allowedValues | length > 0) then
            "Allowed Values: \(.allowedValues | map((.name // .value // .id // "") | tostring) | join(", "))"
        else
            ""
        end),
        "---"
    '
}

cmd_generate_template() {
    if [ "$#" -lt 3 ]; then
        log_error "Usage: ./jira.sh generate-template <PROJECT> <ISSUE_TYPE> <OUTPUT_FILE> [options]"
        exit 1
    fi

    local project="$1"
    local issue_type="$2"
    local output_file="$3"
    shift 3

    local required_fields="false"
    local filters=()
    local update_existing="false"

    # Parse optional arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --required-fields)
                required_fields="true"
                shift
                ;;
            --required-only)
                # Backward compatibility alias for --required-fields
                log_verbose "Note: --required-only is deprecated, use --required-fields instead"
                required_fields="true"
                shift
                ;;
            --filter)
                if [ -z "$2" ]; then
                    log_error "Error: --filter requires a value."
                    return 1
                fi
                filters+=("$2")
                shift 2
                ;;
            --update)
                update_existing="true"
                shift
                ;;
            --add-to-existing)
                # Backward compatibility alias for --update
                log_verbose "Note: --add-to-existing is deprecated, use --update instead"
                update_existing="true"
                shift
                ;;
            *)
                log_error "Error: Unknown option '$1'"
                echo "Usage: ./jira.sh generate-template <PROJECT> <ISSUE_TYPE> <OUTPUT_FILE> [options]"
                return 1
                ;;
        esac
    done

    log_info "Generating template for project ${project}, issue type ${issue_type}..."

    if [ "${#filters[@]}" -gt 0 ]; then
        log_info "Filtering fields by name (case-insensitive): ${filters[*]}"
    fi

    # Check if output file already exists
    local is_updating="false"
    if [ -f "${output_file}" ]; then
        if [ "${update_existing}" = "true" ]; then
            log_info "Will add missing fields to existing template '${output_file}'"
            is_updating="true"
        else
            log_error "Output file already exists: ${output_file}"
            log_error "Use --update to update it, or choose a different name."
            exit 1
        fi
    fi

    local metadata
    if ! metadata=$(get_metadata "${project}" "${issue_type}"); then
        log_error "Failed to get metadata. Try fetching it first:"
        log_error "  ./jira.sh fetch-metadata ${project} ${issue_type}"
        exit 1
    fi

    # Extract all fields or only required fields, with optional name filtering
    local fields_json

    # Build filter condition for jq
    local filter_condition=""
    if [ "${#filters[@]}" -gt 0 ]; then
        # Build OR expression: (.value.name | test("filter1"; "i")) or (.value.name | test("filter2"; "i")) ...
        local filter_parts=()
        for filter in "${filters[@]}"; do
            filter_parts+=("(.value.name | test(\"${filter}\"; \"i\"))")
        done
        # Join with " or "
        filter_condition="| select($(IFS=' or '; echo "${filter_parts[*]}"))"
    fi

    if [ "${required_fields}" = "true" ]; then
        log_verbose "Including only required fields..."
        fields_json=$(echo "${metadata}" | jq -c "
            .projects[0].issuetypes[0].fields
            | to_entries[]
            | select(.value.required == true)
            ${filter_condition}
            | {key: .key, name: .value.name, schema: .value.schema, required: .value.required, allowedValues: .value.allowedValues}
        ")
    else
        log_verbose "Including all available fields..."
        fields_json=$(echo "${metadata}" | jq -c "
            .projects[0].issuetypes[0].fields
            | to_entries[]
            ${filter_condition}
            | {key: .key, name: .value.name, schema: .value.schema, required: .value.required, allowedValues: .value.allowedValues}
        ")
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
        echo "# Generated by jira.sh" >> "${output_file}"
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
        schema_type=$(echo "${field_json}" | jq -r '.schema.type // "string"')

        local is_required
        is_required=$(echo "${field_json}" | jq -r '.required // false')

        # Determine a sensible default value based on schema type
        # Use interactive placeholders by default - users can change to static if desired
        local default_value

        # Check if this is a multi-line field based on Jira schema information
        # This is more reliable than pattern matching on field names
        local is_multiline_field="false"

        # Check for textarea custom fields
        local custom_type
        custom_type=$(echo "${field_json}" | jq -r '.schema.custom // ""')
        if [[ "${custom_type}" == *"textarea"* ]]; then
            is_multiline_field="true"
            log_debug "Auto-detected multi-line field: ${field_name} (textarea custom field)"
        fi

        # Check for standard system fields that are multi-line
        local system_type
        system_type=$(echo "${field_json}" | jq -r '.schema.system // ""')
        if [[ "${system_type}" == "description" ]] || [[ "${system_type}" == "environment" ]] || [[ "${system_type}" == "comment" ]]; then
            is_multiline_field="true"
            log_debug "Auto-detected multi-line field: ${field_name} (system field: ${system_type})"
        fi

        case "${schema_type}" in
            string)
                if [ "${is_multiline_field}" = "true" ]; then
                    default_value="'{{PROMPT_MULTI: Enter ${field_name}}}'"
                else
                    default_value="'{{PROMPT: Enter ${field_name}}}'"
                fi
                ;;
            number)
                default_value="'{{PROMPT: Enter ${field_name}}}'"
                ;;
            array)
                # For arrays, provide guidance in the prompt
                default_value="'{{PROMPT: Enter ${field_name} (comma-separated)}}'"
                ;;
            option)
                # Check if there are allowed values
                # Try multiple fields: name, value, or id (in that order of preference)
                # Convert to string and filter out empty values
                local allowed_values
                allowed_values=$(echo "${field_json}" | jq -r '.allowedValues // [] | map((.name // .value // .id // "") | tostring) | map(select(. != "" and . != "null")) | join(", ")')

                # If we got empty values, check the count to see if options exist but are empty
                local options_count
                options_count=$(echo "${field_json}" | jq -r '.allowedValues // [] | length')

                # Determine if this uses 'name' or 'value' based on the first allowed value
                # Custom select fields use 'value', standard fields like priority use 'name'
                local option_key="name"
                if [ "${options_count}" -gt 0 ]; then
                    local first_value_has_value
                    first_value_has_value=$(echo "${field_json}" | jq -r '.allowedValues[0] | has("value")')
                    if [ "${first_value_has_value}" = "true" ]; then
                        option_key="value"
                    fi
                fi

                if [ -n "${allowed_values}" ] && [ "${allowed_values}" != "" ] && [ "${allowed_values}" != "null" ]; then
                    default_value="{${option_key}: '{{PROMPT: Choose ${field_name} [${allowed_values}]}}'}"
                elif [ "${options_count}" -gt 0 ]; then
                    # Options exist but have empty names - provide helpful message
                    default_value="{${option_key}: '{{PROMPT: Enter ${field_name} (${options_count} options - check Jira UI)}}'}"
                else
                    default_value="{${option_key}: '{{PROMPT: Enter ${field_name}}}'}"
                fi
                ;;
            user)
                default_value="{name: '{{PROMPT: Enter username for ${field_name}}}'}"
                ;;
            priority)
                default_value="{name: '{{PROMPT: Enter priority}}'}"
                ;;
            project)
                # Skip project field as it's set by the script
                continue
                ;;
            issuetype)
                # Set the issue type to the one specified (this is static)
                default_value="{name: '${issue_type}'}"
                ;;
            date|datetime)
                default_value="'{{PROMPT: Enter ${field_name} (YYYY-MM-DD or ISO format)}}'"
                ;;
            *)
                default_value="'{{PROMPT: Enter ${field_name}}}'"
                ;;
        esac

        # Build comment with field information
        local comment="${field_name}"
        if [ "${is_required}" = "true" ]; then
            comment="${comment} [REQUIRED]"
        fi
        comment="${comment} - Type: ${schema_type}"

        # Add allowed values to comment if available
        # Try multiple fields: name, value, or id (in that order of preference)
        # Convert to string and filter out empty values
        local allowed_values
        allowed_values=$(echo "${field_json}" | jq -r 'if .allowedValues and (.allowedValues | length > 0) then .allowedValues | map((.name // .value // .id // "") | tostring) | map(select(. != "" and . != "null")) | join(", ") else "" end')

        if [ -n "${allowed_values}" ] && [ "${allowed_values}" != "" ] && [ "${allowed_values}" != "null" ]; then
            comment="${comment} - Allowed: ${allowed_values}"
        else
            # Check if options exist but have empty names
            local options_count
            options_count=$(echo "${field_json}" | jq -r '.allowedValues // [] | length')
            if [ "${options_count}" -gt 0 ]; then
                comment="${comment} - ${options_count} options (check Jira UI for values)"
            fi
        fi

        # Write the field to YAML with comment
        if [ "${is_updating}" = "true" ]; then
            # Use yq to add field to existing YAML
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
        log_info "  2. Create a ticket with: ./jira.sh create-from-template ${project} ${output_file}"
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

cmd_fetch_metadata() {
    if [ "$#" -lt 2 ]; then
        log_error "Usage: ./jira.sh fetch-metadata <PROJECT> <ISSUE_TYPE> [--refresh]"
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
                echo "Usage: ./jira.sh fetch-metadata <PROJECT> <ISSUE_TYPE> [--refresh]"
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
                # Not an option, must be the command
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

    local command="$1"
    shift

    case "$command" in
        create)
            cmd_create "$@"
            ;;
        create-from-template)
            cmd_create_from_template "$@"
            ;;
        update)
            cmd_update "$@"
            ;;
        list-fields)
            cmd_list_fields "$@"
            ;;
        list-issue-types)
            cmd_list_issue_types "$@"
            ;;
        show-required)
            cmd_show_required "$@"
            ;;
        generate-template)
            cmd_generate_template "$@"
            ;;
        fetch-metadata)
            cmd_fetch_metadata "$@"
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
