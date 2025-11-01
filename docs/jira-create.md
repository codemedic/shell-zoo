# Jira Create

A comprehensive Bash script to create Jira tickets with validation, metadata caching, and template generation capabilities. This script helps automate ticket creation while ensuring all required fields are properly populated.

## Solution Overview

The `jira-create.sh` script provides multiple subcommands for different ticket creation workflows:

1. **`create-minimal`**: Create a simple ticket with just summary and description
2. **`create-from-template`**: Create a ticket using a YAML template file
3. **`fetch-metadata`**: Fetch and cache field metadata for a project/issue type
4. **`show-required`**: Display required fields for a project/issue type
5. **`generate-template`**: Generate a YAML template with available fields

### Key Features

- **Validation**: Automatically validates required fields before ticket creation
- **Metadata Caching**: Caches field metadata locally to avoid repeated API calls (stored in `~/.jira-cache/`)
- **Template Generation**: Automatically generates YAML templates with sensible defaults
- **Field Discovery**: Filter and find fields by name to build your templates
- **Shared Libraries**: Uses common functions from `functions.sh` (logging, validation) and `functions-jira.sh` (Jira API operations, authentication)

## How to Use

For detailed usage instructions, run the script with the `--help` option:

```bash
./jira-create.sh --help
```

### Global Options

The script supports the following global options (place before the subcommand):

- `--help`: Show help message and exit
- `--log-level <LEVEL>`: Set log level (DEBUG, VERBOSE, INFO, ERROR). Default: INFO
- `--debug`: Shortcut for `--log-level DEBUG` (most verbose output)
- `--verbose`: Shortcut for `--log-level VERBOSE` (detailed output)
- `--quiet`: Shortcut for `--log-level ERROR` (only show errors)

Example:
```bash
jira_run ./jira-create.sh --verbose create-minimal PROJ "My Ticket" "Description"
```

### Step 1: Set Up Environment Variables

The script relies on the following environment variables for Jira authentication:

- `jira_base_url`: Your Jira instance URL (e.g., `https://company.atlassian.net`)
- `jira_user`: Your Jira username (e.g., `user@company.com`)
- `jira_password`: Your Jira API token

It is recommended to use a wrapper function like `jira_run` to set these variables securely.

**For Linux (with KDE Wallet):**

```bash
# Example jira_run function for Linux
# Retrieves the Jira API token from kwallet and sets environment variables
jira_run() {
    jira_password=$(kwallet-query -f MyWalletFolder -r jira-cloud-token kdewallet 2>/dev/null) \
    jira_base_url=https://company.atlassian.net \
    jira_user=user@company.com \
    "$@"
}
```

**For macOS (with Keychain):**

First, add your API token to Keychain Access:

```bash
security add-generic-password -a 'user@company.com' -s 'jira-cloud-token' -w 'YOUR_JIRA_API_TOKEN'
```

Then create the wrapper function:

```bash
# Example jira_run function for macOS
# Retrieves the Jira API token from Keychain and sets environment variables
jira_run() {
    jira_password=$(security find-generic-password -a 'user@company.com' -s 'jira-cloud-token' -w) \
    jira_base_url=https://company.atlassian.net \
    jira_user=user@company.com \
    "$@"
}
```

## Subcommands

### 1. Create Minimal Ticket

Create a simple ticket with just the basic fields:

```bash
jira_run ./jira-create.sh create-minimal <PROJECT> <SUMMARY> <DESCRIPTION> [options]
```

**Options:**
- `--type <TYPE>`: Issue type (default: Task). Common values: Task, Bug, Story, Epic
- `--skip-validation`: Skip validation of required fields

**Examples:**

```bash
# Create a simple task
jira_run ./jira-create.sh create-minimal PROJ "Fix login bug" "Users cannot log in"

# Create a bug
jira_run ./jira-create.sh create-minimal PROJ "Fix login bug" "Users cannot log in" --type Bug

# Skip validation (not recommended)
jira_run ./jira-create.sh create-minimal PROJ "My Task" "Description" --skip-validation
```

**Note**: If your project requires additional fields beyond summary and description, this command will fail validation. Use `show-required` to see what fields are needed, or use `generate-template` to create a complete template.

### 2. Create from Template

Create a ticket using a YAML template file:

```bash
jira_run ./jira-create.sh create-from-template <PROJECT> <YAML_FILE> [options]
```

**Options:**
- `--skip-validation`: Skip validation of required fields

**Example:**

```bash
jira_run ./jira-create.sh create-from-template PROJ my-story.yml
```

### 3. Fetch Metadata

Fetch and cache field metadata for a project and issue type:

```bash
jira_run ./jira-create.sh fetch-metadata <PROJECT> <ISSUE_TYPE> [options]
```

**Options:**
- `--refresh`: Force refresh the cache even if it exists

**Examples:**

```bash
# Fetch metadata for Stories in project PROJ
jira_run ./jira-create.sh fetch-metadata PROJ Story

# Force refresh cached metadata
jira_run ./jira-create.sh fetch-metadata PROJ Story --refresh
```

The metadata is cached in `~/.jira-cache/PROJECT-ISSUETYPE.json` for fast subsequent access.

### 4. Show Required Fields

Display the required fields for a project and issue type:

```bash
jira_run ./jira-create.sh show-required <PROJECT> <ISSUE_TYPE>
```

**Example:**

```bash
jira_run ./jira-create.sh show-required PROJ Story
```

**Output:**
```
Required fields for project PROJ, issue type Story:

Field Key:    summary
Field Name:   Summary
Field Type:   string
---
Field Key:    customfield_10016
Field Name:   Story Points
Field Type:   number
---
...
```

### 5. Generate Template

Generate a YAML template file with available fields:

```bash
jira_run ./jira-create.sh generate-template <PROJECT> <ISSUE_TYPE> <OUTPUT_FILE> [options]
```

**Options:**
- `--required-only`: Only include required fields (default: include all fields)
- `--filter <string>`: Filter fields by name (case-insensitive partial match)
- `--add-to-existing`: Add missing fields to an existing template instead of failing

**Examples:**

```bash
# Generate a complete template with all available fields
jira_run ./jira-create.sh generate-template PROJ Story my-story-template.yml

# Generate a template with only required fields
jira_run ./jira-create.sh generate-template PROJ Story minimal-story.yml --required-only

# Generate a template with only fields containing "Story"
jira_run ./jira-create.sh generate-template PROJ Story story-fields.yml --filter "Story"

# Add new fields to an existing template
jira_run ./jira-create.sh generate-template PROJ Story existing.yml --add-to-existing
```

The generated template will include:
- Comments describing each field (name, type, allowed values)
- Sensible default values based on field types
- TODO markers where you need to fill in values

**Example Generated Template:**

```yaml
# YAML template for creating Story in project PROJ
# Generated by jira-create.sh

fields:

  # Summary [REQUIRED] - Type: string
  summary: 'TODO: Enter Summary'

  # Description [REQUIRED] - Type: string
  description: 'TODO: Enter Description'

  # Issue Type [REQUIRED] - Type: issuetype
  issuetype: {name: 'Story'}

  # Story Points - Type: number
  customfield_10016: 0

  # Sprint - Type: array
  customfield_10020: []

  # Labels - Type: array
  labels: []

  # Priority - Type: priority - Allowed: Highest, High, Medium, Low, Lowest
  priority: {name: 'Medium'}
```

## Workflow Examples

### Workflow 1: Create a Simple Task

The fastest way to create a ticket if your project doesn't require extra fields:

```bash
jira_run ./jira-create.sh create-minimal PROJ "Implement feature X" "Add support for feature X"
```

### Workflow 2: Discover Required Fields and Create Template

When you need to create tickets with custom fields:

```bash
# Step 1: See what fields are required
jira_run ./jira-create.sh show-required PROJ Story

# Step 2: Generate a template with all fields
jira_run ./jira-create.sh generate-template PROJ Story my-story.yml

# Step 3: Edit my-story.yml and fill in the TODO values

# Step 4: Create the ticket
jira_run ./jira-create.sh create-from-template PROJ my-story.yml
```

### Workflow 3: Build Template Incrementally

When you want to discover and add specific fields:

```bash
# Generate template with only required fields
jira_run ./jira-create.sh generate-template PROJ Story my-template.yml --required-only

# Add fields related to "Sprint"
jira_run ./jira-create.sh generate-template PROJ Story my-template.yml --filter "Sprint" --add-to-existing

# Add fields related to "Story Points"
jira_run ./jira-create.sh generate-template PROJ Story my-template.yml --filter "Story Points" --add-to-existing

# Edit the template and create ticket
# ... edit my-template.yml ...
jira_run ./jira-create.sh create-from-template PROJ my-template.yml
```

### Workflow 4: Create Multiple Similar Tickets

When you have a template and want to reuse it:

```bash
# Create template once
jira_run ./jira-create.sh generate-template PROJ Bug bug-template.yml
# ... edit bug-template.yml with common values ...

# Create multiple tickets by copying and modifying the template
cp bug-template.yml bug-001.yml
# ... edit bug-001.yml for specific bug ...
jira_run ./jira-create.sh create-from-template PROJ bug-001.yml

cp bug-template.yml bug-002.yml
# ... edit bug-002.yml for another bug ...
jira_run ./jira-create.sh create-from-template PROJ bug-002.yml
```

## Troubleshooting

### Validation Errors

If you get validation errors about missing required fields:

```bash
# See what fields are required
jira_run ./jira-create.sh show-required PROJ Story

# Generate a template to ensure you have all fields
jira_run ./jira-create.sh generate-template PROJ Story complete.yml
```

### Cache Issues

If you're seeing stale metadata:

```bash
# Refresh the cache
jira_run ./jira-create.sh fetch-metadata PROJ Story --refresh
```

### API Errors

For debugging API issues:

```bash
# Use debug mode to see full API requests and responses
jira_run ./jira-create.sh --debug create-minimal PROJ "Test" "Description"
```

## Environment & Dependencies

This solution is built to run in a Bash shell environment (Linux/macOS) and relies on:

- **`bash`**: The shell interpreter
- **`curl`**: Used to make REST API calls to Jira
- **`jq`**: A command-line JSON processor for parsing API responses
- **`yq`**: A command-line YAML processor for template files
- **`base64`**: For encoding credentials

The script will check for these dependencies on startup and report any missing tools.

## Related Scripts

- **[jira-soother.sh](jira-soother.md)**: For updating existing tickets with templates
- **`functions-jira.sh`**: Shared Jira API functions used by both scripts
