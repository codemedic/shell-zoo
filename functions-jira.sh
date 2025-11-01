#!/usr/bin/env bash

# Reusable Jira-specific functions for shell scripts

# --- Configuration Validation ---

# Validate that required Jira environment variables are set
validate_jira_env() {
    : "${jira_base_url:?Environment variable jira_base_url not set.}"
    : "${jira_user:?Environment variable jira_user not set.}"
    : "${jira_password:?Environment variable jira_password not set.}"
}

# --- Authentication ---

# Create Basic Auth header for Jira API
# Returns: Authorization header string
get_jira_auth_header() {
    local auth_string
    auth_string=$(echo -n "${jira_user}:${jira_password}" | base64)
    echo "Authorization: Basic ${auth_string}"
}

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

    local auth_header
    auth_header=$(get_jira_auth_header)

    local response
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -H "${auth_header}" \
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

    local auth_header
    auth_header=$(get_jira_auth_header)

    local response
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -X POST \
        -H "${auth_header}" \
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

    local auth_header
    auth_header=$(get_jira_auth_header)

    local response
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -X PUT \
        -H "${auth_header}" \
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
