#!/usr/bin/env bash

# Reusable Jira-specific functions for shell scripts

# --- Interactive Template Support ---

# Check if a value is an interactive placeholder
# Args: $1 - value to check
# Returns: 0 if it's a placeholder, 1 otherwise
is_interactive_placeholder() {
    local value="$1"
    # Match patterns like {{PROMPT: text}}, {{INPUT: text}}, {{PROMPT_MULTI: text}}, or {{INPUT_MULTI: text}}
    [[ "${value}" =~ ^\{\{(PROMPT|INPUT|PROMPT_MULTI|INPUT_MULTI):[[:space:]]*(.+)\}\}$ ]]
}

# Extract prompt text from placeholder
# Args: $1 - placeholder value (e.g., "{{PROMPT: Enter summary}}")
# Returns: The prompt text
extract_prompt_text() {
    local value="$1"
    if [[ "${value}" =~ ^\{\{(PROMPT|INPUT|PROMPT_MULTI|INPUT_MULTI):[[:space:]]*(.+)\}\}$ ]]; then
        echo "${BASH_REMATCH[2]}"
    fi
}

# Check if placeholder is multi-line type
# Args: $1 - placeholder value
# Returns: 0 if multi-line, 1 otherwise
is_multiline_placeholder() {
    local value="$1"
    [[ "${value}" =~ ^\{\{(PROMPT_MULTI|INPUT_MULTI):[[:space:]]*.+\}\}$ ]]
}

# Prompt user for input interactively
# Args: $1 - field name, $2 - prompt text, $3 - is_multiline (true/false)
# Returns: User input
prompt_user_input() {
    local field_name="$1"
    local prompt_text="$2"
    local is_multiline="${3:-false}"

    # Display the prompt text as the main label (it's the human-readable field name/question)
    log_info "${prompt_text}"
    log_verbose "(Field ID: ${field_name})"

    local user_input

    if [ "${is_multiline}" = "true" ]; then
        # Multi-line input mode
        echo "  [Enter multi-line text. Type 'END' on a new line when finished]" >&2
        echo "" >&2

        local lines=()
        local line
        while IFS= read -r line < /dev/tty; do
            # Check if user entered END to finish
            if [ "${line}" = "END" ]; then
                break
            fi
            lines+=("${line}")
        done

        # Join lines with actual newlines
        user_input=$(printf "%s\n" "${lines[@]}" | sed '$d' || printf "%s\n" "${lines[@]}")

        # Remove trailing newline if lines array is not empty
        if [ "${#lines[@]}" -gt 0 ]; then
            # Join all lines with newline, but remove the last extra newline
            user_input=$(IFS=$'\n'; echo "${lines[*]}")
        fi
    else
        # Single-line input mode
        echo -n "  > " >&2
        read -r user_input < /dev/tty
    fi

    echo "${user_input}"
}

# Process JSON and replace interactive placeholders with user input
# Args: $1 - JSON string, $2 - enable interactive mode (true/false)
# Returns: Modified JSON with placeholders replaced
process_interactive_template() {
    local json="$1"
    local interactive="${2:-true}"

    if [ "${interactive}" != "true" ]; then
        # Check for any placeholders and error if found
        if echo "${json}" | jq -e '.. | select(type == "string" and test("^\\{\\{(PROMPT|INPUT|PROMPT_MULTI|INPUT_MULTI):"))' > /dev/null 2>&1; then
            log_error "Template contains interactive placeholders but interactive mode is disabled."
            log_error "Use --interactive flag or remove placeholders from template."
            return 1
        fi
        echo "${json}"
        return 0
    fi

    log_info "Processing interactive template..."
    echo "" >&2

    # Extract all string values with their paths
    local paths_and_values
    paths_and_values=$(echo "${json}" | jq -r 'paths(type == "string") as $p | "\($p | join("."))\t\(getpath($p))"')

    local modified_json="${json}"

    while IFS=$'\t' read -r path value; do
        if is_interactive_placeholder "${value}"; then
            local prompt_text
            prompt_text=$(extract_prompt_text "${value}")

            # Extract field name from path (last component)
            local field_name
            field_name=$(echo "${path}" | awk -F'.' '{print $NF}')

            # Check if this is a multi-line placeholder
            local is_multiline="false"
            if is_multiline_placeholder "${value}"; then
                is_multiline="true"
            fi

            # Get user input
            local user_input
            user_input=$(prompt_user_input "${field_name}" "${prompt_text}" "${is_multiline}")

            # Validate path contains only safe characters to prevent injection
            if [[ ! "${path}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                log_error "Invalid field path detected: ${path}"
                log_error "Paths must contain only alphanumeric characters, dots, hyphens, and underscores."
                return 1
            fi

            # Escape the input for JSON
            local escaped_input
            escaped_input=$(echo -n "${user_input}" | jq -R -s '.')

            # Replace in JSON using jq with safe parameter passing
            # Convert dot-separated path like "fields.summary" to array ["fields", "summary"]
            local path_array
            path_array=$(echo "${path}" | jq -R 'split(".")')

            # Update the JSON using setpath() with safely passed arguments
            local updated_json
            if ! updated_json=$(echo "${modified_json}" | jq \
                --argjson path "${path_array}" \
                --argjson value "${escaped_input}" \
                'setpath($path; $value)'); then
                log_error "Failed to update field '${field_name}' in template."
                return 1
            fi
            modified_json="${updated_json}"
        fi
    done <<< "${paths_and_values}"

    echo "" >&2
    log_info "Interactive input complete."
    echo "${modified_json}"
}

# --- Configuration Validation ---

# Validate that required Jira environment variables are set
validate_jira_env() {
    : "${jira_base_url:?Environment variable jira_base_url not set.}"
    : "${jira_user:?Environment variable jira_user not set.}"
    : "${jira_password:?Environment variable jira_password not set.}"
}

# --- Authentication ---

# --- HTTP Response Handling ---

# Parse HTTP status from curl response with -w "\nHTTP_STATUS:%{http_code}"
# Args: $1 - full response string
# Returns: HTTP status code
parse_http_status() {
    local response="$1"
    echo "${response}" | grep "HTTP_STATUS:" | cut -d: -f2
}

# Parse HTTP body from curl response with -w "\nHTTP_STATUS:%{http_code}"
# Args: $1 - full response string
# Returns: response body without status line
parse_http_body() {
    local response="$1"
    echo "${response}" | sed '$d' # Remove last line (the status)
}

# Check if HTTP status indicates success for GET requests
# Args: $1 - HTTP status code
# Returns: 0 if success (200), 1 otherwise
is_http_success_get() {
    local status="$1"
    [ "$status" -eq 200 ]
}

# Check if HTTP status indicates success for POST requests
# Args: $1 - HTTP status code
# Returns: 0 if success (201), 1 otherwise
is_http_success_post() {
    local status="$1"
    [ "$status" -eq 201 ]
}

# Check if HTTP status indicates success for PUT requests
# Args: $1 - HTTP status code
# Returns: 0 if success (204 or 200), 1 otherwise
is_http_success_put() {
    local status="$1"
    [ "$status" -eq 204 ] || [ "$status" -eq 200 ]
}

# --- YAML/JSON Handling ---

# Validate that a YAML file exists and is valid YAML/JSON
# Args: $1 - path to YAML file
# Returns: 0 if valid, 1 otherwise
validate_yaml_file() {
    local yaml_file="$1"

    if [ ! -f "${yaml_file}" ]; then
        log_error "YAML file not found at: ${yaml_file}"
        return 1
    fi

    # Try to convert to JSON and validate
    local json_content
    if ! json_content=$(yq -o=json '.' "${yaml_file}" 2>/dev/null); then
        log_error "Failed to read YAML file: ${yaml_file}"
        return 1
    fi

    if ! echo "${json_content}" | jq . > /dev/null 2>&1; then
        log_error "The file '${yaml_file}' does not contain valid YAML/JSON."
        return 1
    fi

    return 0
}

# --- Field Default Values ---

# Get a sensible default value for a Jira field based on its schema type
# Args: $1 - schema type, $2 - field name, $3 - allowed values (comma-separated, optional), $4 - issue type (for issuetype fields)
# Returns: default value string suitable for YAML
get_field_default_value() {
    local schema_type="$1"
    local field_name="$2"
    local allowed_values="${3:-}"
    local issue_type="${4:-Task}"

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
            if [ -n "${allowed_values}" ]; then
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
            # Skip project field - it's set by the script
            return 1
            ;;
        issuetype)
            default_value="{name: '${issue_type}'}"
            ;;
        date|datetime)
            default_value="'TODO: YYYY-MM-DD or YYYY-MM-DDTHH:mm:ss.sssZ'"
            ;;
        *)
            default_value="'TODO'"
            ;;
    esac

    echo "${default_value}"
}

# --- Field Comments ---

# Build a comment string for a field with metadata
# Args: $1 - field name, $2 - is required (true/false), $3 - schema type, $4 - allowed values (comma-separated, optional)
# Returns: comment string
build_field_comment() {
    local field_name="$1"
    local is_required="$2"
    local schema_type="$3"
    local allowed_values="${4:-}"

    local comment="${field_name}"

    if [ "${is_required}" = "true" ]; then
        comment="${comment} [REQUIRED]"
    fi

    comment="${comment} - Type: ${schema_type}"

    if [ -n "${allowed_values}" ]; then
        comment="${comment} - Allowed: ${allowed_values}"
    fi

    echo "${comment}"
}

# --- Jira API Calls ---

# Make a Jira API GET request
# Args: $1 - API endpoint path (e.g., "/rest/api/2/field")
# Sets global variables: jira_response_status, jira_response_body
jira_api_get() {
    local endpoint="$1"
    local url="${jira_base_url}${endpoint}"

    log_debug "GET ${url}"

    local response
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -u "${jira_user}:${jira_password}" \
        -H "Accept: application/json" \
        "${url}")

    jira_response_status=$(parse_http_status "${response}")
    jira_response_body=$(parse_http_body "${response}")

    log_debug "HTTP status: ${jira_response_status}"

    if ! is_http_success_get "${jira_response_status}"; then
        log_error "API request failed. HTTP Status: ${jira_response_status}"
        log_error "Response Body:"
        echo "${jira_response_body}" | jq . >&2
        return 1
    fi

    return 0
}

# Make a Jira API POST request
# Args: $1 - API endpoint path, $2 - JSON payload
# Sets global variables: jira_response_status, jira_response_body
jira_api_post() {
    local endpoint="$1"
    local payload="$2"
    local url="${jira_base_url}${endpoint}"

    log_debug "POST ${url}"
    log_debug "Payload: ${payload}"

    local response
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -X POST \
        -u "${jira_user}:${jira_password}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --data "${payload}" \
        "${url}")

    jira_response_status=$(parse_http_status "${response}")
    jira_response_body=$(parse_http_body "${response}")

    log_debug "HTTP status: ${jira_response_status}"

    if ! is_http_success_post "${jira_response_status}"; then
        log_error "API request failed. HTTP Status: ${jira_response_status}"
        log_error "Response Body:"
        echo "${jira_response_body}" | jq . >&2
        return 1
    fi

    return 0
}

# Make a Jira API PUT request
# Args: $1 - API endpoint path, $2 - JSON payload
# Sets global variables: jira_response_status, jira_response_body
jira_api_put() {
    local endpoint="$1"
    local payload="$2"
    local url="${jira_base_url}${endpoint}"

    log_debug "PUT ${url}"
    log_debug "Payload: ${payload}"

    local response
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -X PUT \
        -u "${jira_user}:${jira_password}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --data "${payload}" \
        "${url}")

    jira_response_status=$(parse_http_status "${response}")
    jira_response_body=$(parse_http_body "${response}")

    log_debug "HTTP status: ${jira_response_status}"

    if ! is_http_success_put "${jira_response_status}"; then
        log_error "API request failed. HTTP Status: ${jira_response_status}"
        log_error "Response Body:"
        echo "${jira_response_body}" | jq . >&2
        return 1
    fi

    return 0
}

# --- Global Options Parsing ---

# Parse common global options (--help, --log-level, --debug, --verbose, --quiet)
# Args: all command-line arguments
# Sets: LOG_LEVEL environment variable
# Returns: remaining arguments after global options via stdout
parse_global_options() {
    # Set default log level
    export LOG_LEVEL="${LOG_LEVEL:-INFO}"

    local remaining_args=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help)
                return 255  # Special return code for help
                ;;
            --log-level)
                if [ -z "$2" ]; then
                    log_error "Error: --log-level requires a value (DEBUG, VERBOSE, INFO, ERROR)."
                    return 1
                fi
                # Validate log level
                case "$2" in
                    DEBUG|VERBOSE|INFO|ERROR)
                        export LOG_LEVEL="$2"
                        ;;
                    *)
                        log_error "Error: Invalid log level '$2'. Must be one of: DEBUG, VERBOSE, INFO, ERROR."
                        return 1
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
                remaining_args+=("$1")
                shift
                ;;
            *)
                # Not an option, add to remaining
                remaining_args+=("$1")
                shift
                ;;
        esac
    done

    # Return remaining arguments
    printf '%s\n' "${remaining_args[@]}"
    return 0
}
