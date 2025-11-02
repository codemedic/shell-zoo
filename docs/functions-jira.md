# Jira Functions Library

The `functions-jira.sh` library provides reusable functions for interacting with the Jira REST API. It's designed to be sourced by Jira-related scripts to provide consistent authentication, API interaction, validation, and error handling.

## Overview

This library is used by `jira.sh` to provide consistent authentication, API interaction, validation, and error handling for all Jira operations.

### Key Features

- **Centralized Authentication**: Single implementation of Basic Auth for Jira API
- **HTTP Wrappers**: Simplified GET, POST, and PUT operations with error handling
- **Response Parsing**: Consistent HTTP status and body extraction
- **Validation Helpers**: YAML file validation and environment variable checking
- **Field Utilities**: Functions for generating field defaults and comments
- **Interactive Templates**: Support for placeholder-based interactive field input

## Usage

Source the library in your script:

```bash
# shellcheck source=functions-jira.sh
source "$(dirname "$0")/functions-jira.sh"
```

**Note**: This library depends on `functions.sh` for logging functions. Make sure to source both:

```bash
# shellcheck source=functions.sh
source "$(dirname "$0")/functions.sh"

# shellcheck source=functions-jira.sh
source "$(dirname "$0")/functions-jira.sh"
```

## Environment Variables

The library expects the following environment variables to be set:

- `jira_base_url`: Your Jira instance URL (e.g., `https://company.atlassian.net`)
- `jira_user`: Your Jira username (e.g., `user@company.com`)
- `jira_password`: Your Jira API token

## Function Reference

### Interactive Template Support

#### `is_interactive_placeholder(value)`

Check if a value is an interactive placeholder.

**Parameters:**
- `$1`: Value to check

**Returns:**
- Exit code 0 if it's a placeholder (matches `{{PROMPT: ...}}` or `{{INPUT: ...}}`)
- Exit code 1 otherwise

**Usage:**
```bash
if is_interactive_placeholder "{{PROMPT: Enter summary}}"; then
    echo "This is a placeholder"
fi
```

#### `extract_prompt_text(value)`

Extract prompt text from a placeholder.

**Parameters:**
- `$1`: Placeholder value (e.g., `"{{PROMPT: Enter summary}}"`)

**Returns:** The prompt text (e.g., `"Enter summary"`)

**Usage:**
```bash
prompt_text=$(extract_prompt_text "{{PROMPT: Enter summary}}")
# Output: "Enter summary"
```

#### `prompt_user_input(field_name, prompt_text, is_multiline)`

Prompt user for input interactively.

**Parameters:**
- `$1`: Field name (for display purposes)
- `$2`: Prompt text (question to ask)
- `$3`: Is multiline (optional, default: "false"). Use "true" for multi-line input

**Returns:** User input from stdin

**Usage:**
```bash
# Single-line input
user_input=$(prompt_user_input "summary" "Enter task summary" "false")

# Multi-line input
description=$(prompt_user_input "description" "Enter description" "true")
# For multi-line, user types 'END' on a new line to finish
```

#### `process_interactive_template(json, interactive)`

Process JSON and replace interactive placeholders with user input.

**Parameters:**
- `$1`: JSON string (typically from YAML template converted to JSON)
- `$2`: Enable interactive mode (`true` or `false`)

**Returns:**
- Modified JSON with placeholders replaced by user input
- Exit code 0 on success, 1 if placeholders found in non-interactive mode

**Supported Placeholder Types:**
- `{{PROMPT: text}}` - Single-line input prompt
- `{{INPUT: text}}` - Single-line input prompt (alias)
- `{{PROMPT_MULTI: text}}` - Multi-line input prompt (type 'END' to finish)
- `{{INPUT_MULTI: text}}` - Multi-line input prompt (alias)

**Behavior:**
- If `interactive="true"`: Prompts user for each placeholder found
  - Single-line placeholders: reads one line of input
  - Multi-line placeholders: reads multiple lines until user types 'END'
- If `interactive="false"`: Validates no placeholders exist, errors if found
- Automatically handles JSON escaping of user input

**Usage:**
```bash
# Interactive mode - single-line
json='{"fields": {"summary": "{{PROMPT: Enter summary}}"}}'
if processed=$(process_interactive_template "${json}" "true"); then
    echo "Processed: ${processed}"
fi

# Interactive mode - multi-line
json='{"fields": {"description": "{{PROMPT_MULTI: Enter description}}"}}'
if processed=$(process_interactive_template "${json}" "true"); then
    # User will be prompted to enter multi-line text, ending with 'END'
    echo "Processed: ${processed}"
fi

# Non-interactive mode (validates no placeholders)
if processed=$(process_interactive_template "${json}" "false"); then
    echo "No placeholders found"
else
    echo "Error: Template contains placeholders but interactive mode disabled"
fi
```

**Example Flow:**

```bash
# Input JSON with placeholders
json='{"fields": {"summary": "{{PROMPT: Enter summary}}", "description": "{{PROMPT_MULTI: Enter description}}"}}'

# Process interactively
processed=$(process_interactive_template "${json}" "true")

# User sees:
#   [INFO] Processing interactive template...
#
#   [INFO] Field: summary
#     Enter summary: My new task
#
#   [INFO] Interactive input complete.

# Output: {"fields": {"summary": "My new task", "description": "Static text"}}
```

### Configuration & Validation

#### `validate_jira_env()`

Validates that required Jira environment variables are set.

**Usage:**
```bash
validate_jira_env
```

**Behavior:**
- Checks for `jira_base_url`, `jira_user`, and `jira_password`
- Exits with error if any variable is not set
- Should be called after `--help` processing to allow help without credentials

### Authentication

#### `get_jira_auth_header()`

Creates a Basic Authentication header for Jira API calls.

**Returns:** Authorization header string

**Usage:**
```bash
auth_header=$(get_jira_auth_header)
# Output: "Authorization: Basic <base64-encoded-credentials>"
```

**Note:** This function is primarily used internally by the API wrapper functions.

### HTTP Response Parsing

#### `parse_http_status(response)`

Extracts the HTTP status code from a curl response.

**Parameters:**
- `$1`: Full response string from curl (with `-w "\nHTTP_STATUS:%{http_code}"`)

**Returns:** HTTP status code (e.g., `200`, `201`, `404`)

**Usage:**
```bash
response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" ...)
status=$(parse_http_status "${response}")
```

#### `parse_http_body(response)`

Extracts the response body from a curl response.

**Parameters:**
- `$1`: Full response string from curl

**Returns:** Response body without the status line

**Usage:**
```bash
response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" ...)
body=$(parse_http_body "${response}")
```

### HTTP Status Validation

#### `is_http_success_get(status)`

Checks if HTTP status indicates success for GET requests.

**Parameters:**
- `$1`: HTTP status code

**Returns:**
- Exit code 0 if status is 200 (success)
- Exit code 1 otherwise

**Usage:**
```bash
if is_http_success_get "${status}"; then
    echo "GET request succeeded"
fi
```

#### `is_http_success_post(status)`

Checks if HTTP status indicates success for POST requests.

**Parameters:**
- `$1`: HTTP status code

**Returns:**
- Exit code 0 if status is 201 (created)
- Exit code 1 otherwise

#### `is_http_success_put(status)`

Checks if HTTP status indicates success for PUT requests.

**Parameters:**
- `$1`: HTTP status code

**Returns:**
- Exit code 0 if status is 204 or 200 (success/no content)
- Exit code 1 otherwise

### YAML/JSON Validation

#### `validate_yaml_file(yaml_file)`

Validates that a YAML file exists and contains valid YAML/JSON.

**Parameters:**
- `$1`: Path to YAML file

**Returns:**
- Exit code 0 if valid
- Exit code 1 if file doesn't exist or contains invalid YAML/JSON

**Usage:**
```bash
if validate_yaml_file "my-template.yml"; then
    echo "YAML file is valid"
else
    echo "YAML file is invalid or missing"
fi
```

### Jira API Calls

These functions provide a high-level interface to the Jira REST API with automatic error handling.

#### `jira_api_get(endpoint)`

Makes a GET request to the Jira API.

**Parameters:**
- `$1`: API endpoint path (e.g., `/rest/api/2/field`)

**Sets Global Variables:**
- `jira_response_status`: HTTP status code
- `jira_response_body`: Response body

**Returns:**
- Exit code 0 on success (HTTP 200)
- Exit code 1 on failure (logs error automatically)

**Usage:**
```bash
if jira_api_get "/rest/api/2/field"; then
    echo "Fields: ${jira_response_body}"
else
    echo "Failed to fetch fields"
fi
```

**Example:**
```bash
# Fetch all fields
jira_api_get "/rest/api/2/field"
fields=$(echo "${jira_response_body}" | jq -r '.[].name')

# Fetch issue details
jira_api_get "/rest/api/2/issue/PROJ-123"
summary=$(echo "${jira_response_body}" | jq -r '.fields.summary')
```

#### `jira_api_post(endpoint, payload)`

Makes a POST request to the Jira API.

**Parameters:**
- `$1`: API endpoint path (e.g., `/rest/api/2/issue`)
- `$2`: JSON payload as string

**Sets Global Variables:**
- `jira_response_status`: HTTP status code
- `jira_response_body`: Response body

**Returns:**
- Exit code 0 on success (HTTP 201)
- Exit code 1 on failure (logs error automatically)

**Usage:**
```bash
json_payload=$(jq -n --arg summary "My Task" '{fields: {summary: $summary}}')
if jira_api_post "/rest/api/2/issue" "${json_payload}"; then
    ticket_key=$(echo "${jira_response_body}" | jq -r '.key')
    echo "Created ticket: ${ticket_key}"
fi
```

#### `jira_api_put(endpoint, payload)`

Makes a PUT request to the Jira API.

**Parameters:**
- `$1`: API endpoint path (e.g., `/rest/api/2/issue/PROJ-123`)
- `$2`: JSON payload as string

**Sets Global Variables:**
- `jira_response_status`: HTTP status code
- `jira_response_body`: Response body

**Returns:**
- Exit code 0 on success (HTTP 204 or 200)
- Exit code 1 on failure (logs error automatically)

**Usage:**
```bash
json_payload=$(yq -o=json '.' template.yml)
if jira_api_put "/rest/api/2/issue/PROJ-123" "${json_payload}"; then
    echo "Successfully updated ticket"
fi
```

### Field Utilities

#### `get_field_default_value(schema_type, field_name, allowed_values, issue_type)`

Generates a sensible default value for a field based on its schema type.

**Parameters:**
- `$1`: Schema type (e.g., `string`, `number`, `array`, `option`, `user`, `priority`)
- `$2`: Field name (for generating descriptive defaults)
- `$3`: Allowed values (comma-separated, optional)
- `$4`: Issue type (used for issuetype fields, optional, default: "Task")

**Returns:**
- Exit code 1 if field should be skipped (e.g., `project` type)
- Exit code 0 and prints default value otherwise

**Default Values by Type:**
- `string`: `'TODO: Enter <field_name>'`
- `number`: `0`
- `array`: `[]`
- `option`: `{name: 'TODO: Choose from: <allowed_values>'}` or `{name: 'TODO'}`
- `user`: `{name: 'username'}`
- `priority`: `{name: 'Medium'}`
- `issuetype`: `{name: '<issue_type>'}`
- `date|datetime`: `'TODO: YYYY-MM-DD or YYYY-MM-DDTHH:mm:ss.sssZ'`
- Other types: `'TODO'`

**Usage:**
```bash
# Get default for a string field
default=$(get_field_default_value "string" "Summary" "" "")
# Output: 'TODO: Enter Summary'

# Get default for an option field with allowed values
default=$(get_field_default_value "option" "Priority" "High, Medium, Low" "")
# Output: {name: 'TODO: Choose from: High, Medium, Low'}

# Check if field should be skipped
if ! default=$(get_field_default_value "project" "Project" "" ""); then
    echo "Skipping project field"
fi
```

#### `build_field_comment(field_name, is_required, schema_type, allowed_values)`

Builds a descriptive comment string for a field.

**Parameters:**
- `$1`: Field name
- `$2`: Is required (`true` or `false`)
- `$3`: Schema type
- `$4`: Allowed values (comma-separated, optional)

**Returns:** Comment string suitable for YAML comments

**Usage:**
```bash
comment=$(build_field_comment "Story Points" "true" "number" "")
# Output: "Story Points [REQUIRED] - Type: number"

comment=$(build_field_comment "Priority" "false" "option" "High, Medium, Low")
# Output: "Priority - Type: option - Allowed: High, Medium, Low"
```

## Complete Example

Here's a complete example script using the library:

```bash
#!/bin/bash
set -euo pipefail

# Source the libraries
source "$(dirname "$0")/functions.sh"
source "$(dirname "$0")/functions-jira.sh"

# Validate environment
validate_jira_env

# Fetch all fields
if jira_api_get "/rest/api/2/field"; then
    log_info "Found fields:"
    echo "${jira_response_body}" | jq -r '.[].name' | head -10
fi

# Create a ticket
payload=$(jq -n \
    --arg project "PROJ" \
    --arg summary "Test Ticket" \
    --arg desc "Created via API" \
    '{
        fields: {
            project: {key: $project},
            summary: $summary,
            description: $desc,
            issuetype: {name: "Task"}
        }
    }')

if jira_api_post "/rest/api/2/issue" "${payload}"; then
    ticket_key=$(echo "${jira_response_body}" | jq -r '.key')
    log_info "Created ticket: ${ticket_key}"

    # Update the ticket
    update_payload='{"fields": {"labels": ["automated", "test"]}}'
    if jira_api_put "/rest/api/2/issue/${ticket_key}" "${update_payload}"; then
        log_info "Successfully updated ticket labels"
    fi
fi
```

## Error Handling

All API functions (`jira_api_get`, `jira_api_post`, `jira_api_put`) automatically:

1. Log the HTTP method and URL at DEBUG level
2. Log the payload (for POST/PUT) at DEBUG level
3. Log the HTTP status at DEBUG level
4. Check for success status codes
5. On error:
   - Log an error message with the HTTP status
   - Pretty-print the JSON error response
   - Return exit code 1

**Example error output:**

```
[ERROR] API request failed. HTTP Status: 400
[ERROR] Response Body:
{
  "errorMessages": [],
  "errors": {
    "customfield_10016": "Story Points is required."
  }
}
```

## Best Practices

1. **Always check return values**: The API functions return exit codes indicating success/failure

   ```bash
   if ! jira_api_get "/rest/api/2/field"; then
       log_error "Cannot proceed without field metadata"
       exit 1
   fi
   ```

2. **Use global variables after successful calls**: Access `jira_response_body` and `jira_response_status` after successful API calls

   ```bash
   jira_api_get "/rest/api/2/issue/PROJ-123"
   summary=$(echo "${jira_response_body}" | jq -r '.fields.summary')
   ```

3. **Validate YAML before processing**: Always use `validate_yaml_file()` before reading YAML files

   ```bash
   if ! validate_yaml_file "${yaml_file}"; then
       exit 1
   fi
   payload=$(yq -o=json '.' "${yaml_file}")
   ```

4. **Use logging functions**: The library works with `functions.sh` logging for consistent output

   ```bash
   log_debug "About to make API call"
   log_info "Processing ticket PROJ-123"
   log_error "Failed to create ticket"
   ```

## Dependencies

This library requires:

- `bash`: Shell interpreter
- `curl`: For HTTP requests
- `jq`: For JSON parsing
- `yq`: For YAML processing
- `base64`: For encoding credentials
- `functions.sh`: For logging functions (`log_debug`, `log_info`, `log_error`)

## Related Documentation

- **[jira.sh](jira.md)**: Unified Jira automation script for all ticket operations
- **`functions.sh`**: General-purpose shell functions (logging, validation)
