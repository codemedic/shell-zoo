# jira.sh - Unified Jira Automation Tool

A comprehensive Bash script for creating and managing Jira tickets with validation, metadata caching, template generation, and field discovery capabilities. This unified script consolidates all Jira operations into a single tool with consistent commands and options.

## Solution Overview

The `jira.sh` script provides eight commands for different Jira workflows:

**Issue Operations:**
1. **`create`**: Create a simple ticket with summary and description
2. **`create-from-template`**: Create a ticket using a YAML template file
3. **`update`**: Update an existing ticket using a YAML template

**Field Discovery:**

4. **`list-fields`**: List global or project-specific Jira fields with optional filtering
5. **`list-issue-types`**: List available issue types for a project
6. **`show-required`**: Display required fields for a project/issue type

**Template Management:**

7. **`generate-template`**: Generate a YAML template with available fields

**Metadata Management:**

8. **`fetch-metadata`**: Fetch and cache field metadata for a project/issue type

### Key Features

- **Unified Interface**: Single script for all Jira operations with consistent command structure
- **Interactive Templates**: Support for placeholders that prompt for user input
  - Single-line: `{{PROMPT:}}` and `{{INPUT:}}`
  - Multi-line: `{{PROMPT_MULTI:}}` and `{{INPUT_MULTI:}}` (auto-detected from Jira field types)
- **Interactive-First Template Generation**: Generated templates use interactive placeholders by default for immediate reuse
- **Validation**: Automatically validates required fields before ticket creation
- **Metadata Caching**: Caches field metadata locally to avoid repeated API calls (stored in `~/.jira-cache/`)
- **Field Discovery**: Filter and find fields by name to build your templates (supports both global and project-specific modes)
- **Shared Libraries**: Uses common functions from `functions.sh` (logging, validation) and `functions-jira.sh` (Jira API operations, authentication)

## How to Use

For detailed usage instructions, run the script with the `--help` option:

```bash
./jira.sh --help
```

### Global Options

The script supports the following global options (place before the command):

- `--help`: Show help message and exit
- `--log-level <LEVEL>`: Set log level (DEBUG, VERBOSE, INFO, ERROR). Default: INFO
- `--debug`: Shortcut for `--log-level DEBUG` (most verbose output)
- `--verbose`: Shortcut for `--log-level VERBOSE` (detailed output)
- `--quiet`: Shortcut for `--log-level ERROR` (only show errors)

Example:
```bash
jira_run ./jira.sh --verbose create PROJ "My Ticket" "Description"
```

### Environment Variables Setup

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

## Template Structure and Organization

Templates are YAML files that define the fields to set when creating or updating tickets. Understanding how to organize and structure your templates is key to effective workflow automation.

### Basic Template Structure

All templates follow this structure:

```yaml
fields:
  <field_id>: <value>
  <field_id>: <value>
  ...
```

### Field Types and Values

Different field types require different value formats:

```yaml
fields:
  # String fields - simple text values
  summary: 'Implement user authentication'
  description: 'Add OAuth 2.0 support'

  # Number fields - numeric values
  customfield_10016: 5  # Story points

  # Object fields - use {name: 'value'} format
  issuetype: {name: 'Story'}
  priority: {name: 'High'}
  assignee: {name: 'john.doe'}
  status: {name: 'In Progress'}

  # Array fields - use list format
  labels: ['backend', 'security', 'api']
  components: [{name: 'Authentication'}, {name: 'API'}]

  # Date/DateTime fields - ISO 8601 format
  duedate: '2024-12-31'
  customfield_10030: '2024-12-31T23:59:59.000Z'

  # User fields - username object
  reporter: {name: 'jane.smith'}

  # Multi-select fields - array of objects
  customfield_10050: [{value: 'Option1'}, {value: 'Option2'}]
```

### Interactive Placeholders

Use placeholders to prompt for values during execution:

```yaml
fields:
  # {{PROMPT: question}} - Single-line input prompt
  summary: '{{PROMPT: Enter ticket summary}}'
  customfield_10016: '{{PROMPT: Enter story points}}'
  assignee: {name: '{{PROMPT: Enter assignee username}}'}

  # {{PROMPT_MULTI: question}} - Multi-line input prompt
  # User types 'END' on a new line to finish input
  description: '{{PROMPT_MULTI: Enter detailed description}}'
  comment: '{{PROMPT_MULTI: Enter update comment}}'

  # {{INPUT: description}} and {{INPUT_MULTI: description}} - Same as PROMPT variants
  # INPUT is semantically the same, just a naming preference
```

**Placeholder Types:**
- `{{PROMPT: text}}` - Single-line input (for short fields like summary, assignee)
- `{{PROMPT_MULTI: text}}` - Multi-line input (for long fields like description)
- `{{INPUT: text}}` - Alias for `{{PROMPT: text}}`
- `{{INPUT_MULTI: text}}` - Alias for `{{PROMPT_MULTI: text}}`

**Multi-line Input Instructions:**
When prompted with `PROMPT_MULTI` or `INPUT_MULTI`:
1. Type or paste your multi-line text
2. Press Enter after each line
3. Type `END` on a new line by itself to finish
4. The text will be properly formatted with line breaks preserved

**Prompt Best Practices:**
- Use descriptive questions: `{{PROMPT: Enter story points (1,2,3,5,8)}}`
- Include context: `{{PROMPT: Enter assignee username (or leave blank for unassigned)}}`
- Use `PROMPT_MULTI` for description, comments, or any long-form text
- Use `PROMPT` for short, single-line values
- Keep prompts concise but clear
- Use field-specific language: "Enter story summary" not "Enter value"

**Note:** When using `generate-template`, the tool automatically selects `PROMPT_MULTI` for textarea fields by reading Jira's field type metadata. This includes standard fields (Description, Environment, Comment) and any custom fields configured as textarea type in Jira. You can manually change any placeholder type by editing the generated template.

### Template Organization Strategies

#### 1. Directory Structure

Organize templates by purpose and project:

```
templates/
├── create/                      # Templates for ticket creation
│   ├── PROJ-story.yml          # Project-specific story template
│   ├── PROJ-bug.yml            # Project-specific bug template
│   └── PROJ-task.yml           # Project-specific task template
├── update/                      # Templates for ticket updates
│   ├── move-to-review.yml      # Workflow transition templates
│   ├── move-to-qa.yml
│   ├── assign-to-team.yml      # Bulk assignment templates
│   └── add-labels.yml          # Field update templates
├── interactive/                 # Interactive templates
│   ├── quick-story.yml         # Mix of static and prompted fields
│   └── bulk-update.yml         # For multiple similar updates
└── team/                        # Team-specific templates
    ├── backend-story.yml       # Team labels and conventions
    └── frontend-story.yml
```

#### 2. Static vs Interactive Templates

**Static Templates** - All values pre-filled, edit file before each use:
```yaml
# templates/create/release-story.yml
fields:
  issuetype: {name: 'Story'}
  summary: 'Release version 2.0.0'
  description: 'Prepare and execute release 2.0.0'
  labels: ['release', 'deployment']
  priority: {name: 'High'}
```

**Interactive Templates** - Prompts for variable values, reusable without editing:
```yaml
# templates/interactive/quick-story.yml
fields:
  issuetype: {name: 'Story'}
  summary: '{{PROMPT: Enter story summary}}'
  description: '{{PROMPT_MULTI: Enter story description}}'  # Multi-line input
  labels: ['backend', 'api']  # Static team labels
  priority: {name: 'Medium'}  # Static default priority
  customfield_10016: '{{PROMPT: Enter story points}}'
```

**Hybrid Templates** - Mix of static team conventions and prompted specifics:
```yaml
# templates/team/backend-story.yml
fields:
  issuetype: {name: 'Story'}
  summary: '{{PROMPT: Enter story summary}}'
  description: '{{PROMPT_MULTI: Enter detailed description}}'  # Multi-line
  labels: ['backend', 'api', 'team-alpha']  # Static team labels
  components: [{name: 'Backend API'}]  # Static component
  priority: {name: 'Medium'}  # Static default
  customfield_10016: '{{PROMPT: Enter story points (1,2,3,5,8)}}'  # Interactive
  assignee: {name: 'backend-team'}  # Static team assignment
```

#### 3. Template Naming Conventions

Use descriptive names that indicate purpose:

```
# Project and type
PROJ-story.yml
PROJ-bug-production.yml
PROJ-task-maintenance.yml

# Workflow state
move-to-in-progress.yml
move-to-code-review.yml
mark-as-done.yml

# Team or component
backend-story.yml
frontend-feature.yml
infrastructure-task.yml

# Purpose
bulk-assign-to-qa.yml
add-sprint-labels.yml
update-priority-high.yml
quick-ticket.yml
```

#### 4. Template Comments and Documentation

Add comments to document template usage:

```yaml
# Backend Story Template
# Purpose: Create backend API stories with team conventions
# Usage: jira_run ./jira.sh create-from-template PROJ templates/team/backend-story.yml
#
# This template pre-fills:
# - Team labels: backend, api, team-alpha
# - Component: Backend API
# - Default priority: Medium
# - Team assignment: backend-team
#
# You will be prompted for:
# - Story summary
# - Detailed description
# - Story points

fields:
  issuetype: {name: 'Story'}
  summary: '{{PROMPT: Enter story summary}}'
  # ... rest of template
```

#### 5. Example Organization for a Team

Real-world example for a development team:

```
jira-templates/
├── README.md                    # Team guide to templates
├── create/
│   ├── story-backend.yml       # Backend stories with team defaults
│   ├── story-frontend.yml      # Frontend stories with team defaults
│   ├── bug-production.yml      # Production bugs (high priority)
│   ├── bug-development.yml     # Development bugs (medium priority)
│   ├── task-maintenance.yml    # Maintenance tasks
│   └── spike-research.yml      # Research spikes
├── update/
│   ├── workflow/
│   │   ├── start-work.yml      # Move to In Progress, assign to self
│   │   ├── submit-review.yml   # Move to Review, add reviewed label
│   │   ├── send-to-qa.yml      # Move to QA, assign to qa-team
│   │   └── mark-done.yml       # Move to Done, add released label
│   ├── assignment/
│   │   ├── assign-backend.yml  # Assign to backend team
│   │   ├── assign-frontend.yml # Assign to frontend team
│   │   └── assign-qa.yml       # Assign to QA team
│   └── maintenance/
│       ├── add-sprint.yml      # Add to current sprint
│       └── bump-priority.yml   # Increase priority
└── interactive/
    ├── quick-ticket.yml        # Fast ticket creation
    └── bulk-update.yml         # Update multiple tickets similarly
```

### Template Compatibility

**Important:** The same template can be used for both `create-from-template` and `update` commands!

Fields that don't apply to the operation are handled gracefully:
- When creating: `status` changes are ignored (new tickets start in default status)
- When updating: `issuetype` is typically ignored (can't change issue type after creation)

This means you can maintain a single set of templates and use them flexibly.

## Commands

### 1. create - Create a Simple Ticket

Create a ticket with just the basic fields:

```bash
jira_run ./jira.sh create <PROJECT> <SUMMARY> <DESCRIPTION> [options]
```

**Options:**
- `--type <TYPE>`: Issue type (default: Task). Common values: Task, Bug, Story, Epic
- `--skip-validation`: Skip validation of required fields

**Examples:**

```bash
# Create a simple task
jira_run ./jira.sh create PROJ "Fix login bug" "Users cannot log in"

# Create a bug
jira_run ./jira.sh create PROJ "Fix login bug" "Users cannot log in" --type Bug

# Skip validation (not recommended)
jira_run ./jira.sh create PROJ "My Task" "Description" --skip-validation
```

**Note**: If your project requires additional fields beyond summary and description, this command will fail validation. Use `show-required` to see what fields are needed, or use `generate-template` to create a complete template.

### 2. create-from-template - Create from Template

Create a ticket using a YAML template file with support for interactive placeholders:

```bash
jira_run ./jira.sh create-from-template <PROJECT> <YAML_FILE> [options]
```

**Options:**
- `--skip-validation`: Skip validation of required fields
- `--interactive`: Force interactive mode (prompt for placeholder values)
- `--no-interactive`: Disable interactive mode (error if placeholders found)

**Interactive Templates:**

Templates can include placeholders for values that should be entered each time:
- `{{PROMPT: question text}}` - Prompts user for input with the given question
- `{{INPUT: field description}}` - Same as PROMPT, prompts for input

**Examples:**

```bash
# Use a static template
jira_run ./jira.sh create-from-template PROJ my-story.yml

# Use an interactive template (auto-detects placeholders)
jira_run ./jira.sh create-from-template PROJ interactive-story.yml

# Force interactive mode
jira_run ./jira.sh create-from-template PROJ my-story.yml --interactive

# Disable interactive mode (will fail if placeholders found)
jira_run ./jira.sh create-from-template PROJ my-story.yml --no-interactive
```

**Example Static Template:**

```yaml
fields:
  issuetype: {name: 'Story'}
  summary: 'Implement user authentication'
  description: 'Add OAuth 2.0 authentication'
  labels: ['backend', 'security']
  priority: {name: 'High'}
```

**Example Interactive Template:**

```yaml
# Mix static and interactive fields
fields:
  issuetype: {name: 'Story'}  # Static - same every time
  summary: '{{PROMPT: Enter story summary}}'  # Interactive - prompts each time
  description: '{{PROMPT_MULTI: Enter detailed description}}'  # Multi-line interactive
  labels: ['backend']  # Static
  customfield_10016: '{{PROMPT: Enter story points (1,2,3,5,8)}}'  # Interactive
  priority: {name: 'Medium'}  # Static
```

When you run the interactive template, you'll be prompted:

```
[INFO] Processing interactive template...

[INFO] Enter story summary
  > Add user profile page
[INFO] Enter detailed description
  > Create a new page for user profile management
[INFO] Enter story points (1,2,3,5,8)
  > 5

[INFO] Interactive input complete.
[INFO] Successfully created ticket PROJ-456!
```

### 3. update - Update Existing Ticket

Update an existing ticket using a YAML template file:

```bash
jira_run ./jira.sh update <TICKET_KEY> <YAML_FILE> [options]
```

**Options:**
- `--interactive`: Force interactive mode (prompt for placeholder values)
- `--no-interactive`: Disable interactive mode (error if placeholders found)

**Examples:**

```bash
# Update with static template
jira_run ./jira.sh update PROJ-123 update-template.yml

# Update with interactive template (auto-detects placeholders)
jira_run ./jira.sh update PROJ-123 interactive-update.yml

# Force interactive mode
jira_run ./jira.sh update PROJ-123 update-template.yml --interactive
```

**Example Static Update Template:**

```yaml
fields:
  status: {name: 'In Review'}
  labels: ['reviewed', 'ready-for-qa']
  assignee: {name: 'qa-team'}
```

**Example Interactive Update Template:**

```yaml
fields:
  status: {name: '{{PROMPT: Enter new status}}'}  # Interactive - prompts each time
  labels: ['reviewed']  # Static - same every time
  assignee: {name: '{{PROMPT: Enter assignee username}}'}  # Interactive
  comment: '{{INPUT: Enter update comment}}'  # Interactive
```

Interactive session output:

```
[INFO] Processing interactive template...

[INFO] Enter new status
  > In Progress
[INFO] Enter assignee username
  > john.doe
[INFO] Enter update comment
  > Starting work on this ticket

[INFO] Interactive input complete.
[INFO] Successfully updated ticket PROJ-123!
```

**Template Compatibility Note:** The same template file can be used for both `create-from-template` and `update` commands. Fields that don't apply to the operation (like `issuetype` for updates or `status` for creation) will be handled appropriately by Jira.

### 4. list-fields - Discover Fields

List available Jira fields with optional filtering.

```bash
jira_run ./jira.sh list-fields [<PROJECT> <ISSUE_TYPE>] [options]
```

**Usage Modes:**

1. **Global Mode** (without PROJECT/ISSUE_TYPE): Lists all global Jira fields (for exploration only)
2. **Project-Specific Mode** (with PROJECT/ISSUE_TYPE): Lists fields available for that specific project/issue type combination

**Options:**
- `--filter <string>`: Case-insensitively filter fields by name (partial match)

**Examples:**

```bash
# List all global fields (exploration only)
jira_run ./jira.sh list-fields

# Find global fields related to "Story Points"
jira_run ./jira.sh list-fields --filter "Story Points"

# List fields available for a specific project and issue type
jira_run ./jira.sh list-fields PROJ Story

# Filter fields for specific project/issue type
jira_run ./jira.sh list-fields PROJ Story --filter "Sprint"
```

**Output Format (Global Mode):**

```json
{
  "id": "customfield_10016",
  "name": "Story Points",
  "schema": "number",
  "items": "none",
  "allowedValues": []
}
```

**Output Format (Project-Specific Mode):**

```json
{
  "id": "customfield_10016",
  "name": "Story Points",
  "schema": "number",
  "items": "none",
  "required": false,
  "allowedValues": []
}
```

**Use Cases:**
- **Global Mode**: Discover all fields in your Jira instance, find field IDs, explore field types
- **Project-Specific Mode**: See exactly which fields are available for a specific project/issue type, identify required fields

**Note:** For creating templates, use `generate-template` which automatically handles project/issue type specific fields and generates correct field formats.

### 5. list-issue-types - List Issue Types

List all available issue types for a project:

```bash
jira_run ./jira.sh list-issue-types <PROJECT>
```

**Example:**

```bash
jira_run ./jira.sh list-issue-types PROJ
```

**Output:**

```
[INFO] Fetching issue types for project PROJ...
[INFO] Available issue types for project PROJ:

  • Story (ID: 10001)
    Description: A user story
    Usage in templates: issuetype: {name: 'Story'}
  • Bug (ID: 10004)
    Description: A problem which impairs or prevents the functions of the product
    Usage in templates: issuetype: {name: 'Bug'}
  • Task (ID: 10002)
    Description: A task that needs to be done
    Usage in templates: issuetype: {name: 'Task'}
  • Epic (ID: 10000)
    Description: A large user story that can be broken down into smaller stories
    Usage in templates: issuetype: {name: 'Epic'}
  • Sub-task (ID: 10003) [SUBTASK]
    Description: A subtask of another issue
    Usage in templates: issuetype: {name: 'Sub-task'}

[INFO] Note: Use the exact name shown above in templates and --type flag.
[INFO]       Names are case-sensitive (e.g., 'Story' not 'story').
```

**Key Points:**
- The command shows the **display name** (what you see in Jira UI)
- The command shows the **ID** for reference
- The **"Usage in templates"** line shows exactly how to specify the issue type in YAML templates
- **[SUBTASK]** marker indicates subtask issue types (which require a parent issue)
- Names are **case-sensitive** - use the exact capitalization shown

**Use Cases:**
- Discover what issue types are available before creating templates
- Verify correct spelling and capitalization for the `--type` flag
- Find the correct name to use when creating tickets programmatically
- Understand which issue types are subtasks (require parent issues)

### 6. show-required - Display Required Fields

Display the required fields for a project and issue type:

```bash
jira_run ./jira.sh show-required <PROJECT> <ISSUE_TYPE>
```

**Example:**

```bash
jira_run ./jira.sh show-required PROJ Story
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

### 7. generate-template - Generate Template File

Generate a YAML template file with available fields:

```bash
jira_run ./jira.sh generate-template <PROJECT> <ISSUE_TYPE> <OUTPUT_FILE> [options]
```

**Options:**
- `--required-fields`: Only include required fields (default: include all fields)
- `--filter <string>`: Filter fields by name (case-insensitive partial match). **Can be specified multiple times** for OR logic
- `--update`: Add missing fields to an existing template instead of failing

**Examples:**

```bash
# Generate a complete template with all available fields
jira_run ./jira.sh generate-template PROJ Story my-story-template.yml

# Generate a template with only required fields
jira_run ./jira.sh generate-template PROJ Story minimal-story.yml --required-fields

# Generate a template with specific fields using multiple filters
jira_run ./jira.sh generate-template PROJ Story story-fields.yml \
  --filter "Sprint" \
  --filter "Story Points" \
  --filter "Labels"

# Combine required fields with additional filtered fields
jira_run ./jira.sh generate-template PROJ Story template.yml --required-fields
jira_run ./jira.sh generate-template PROJ Story template.yml --filter "Sprint" --update

# Add new fields to an existing template
jira_run ./jira.sh generate-template PROJ Story existing.yml --update
```

The generated template will include:
- Comments describing each field (name, type, allowed values)
- **Interactive placeholders** by default for easy reuse:
  - `{{PROMPT:}}` for single-line fields
  - `{{PROMPT_MULTI:}}` for multi-line fields (auto-detected)
- Static values for fields that don't change (like `issuetype`)

**Multi-line Field Auto-Detection:**

The tool automatically uses `{{PROMPT_MULTI:}}` for fields based on their Jira field type:

**Detected from schema metadata:**
- **Custom textarea fields**: Any custom field with type `com.atlassian.jira.plugin.system.customfieldtypes:textarea`
- **Standard system fields**: Description, Environment, Comment

This detection uses Jira's actual field type metadata (from `.schema.custom` and `.schema.system`), making it 100% reliable regardless of field names. Fields like "Testing Notes", "Dependencies", "Acceptance Criteria" will automatically use multi-line input if they're configured as textarea fields in Jira.

Use `VERBOSE=true` to see which fields are detected as multi-line.

**Example Generated Template:**

```yaml
# YAML template for creating Story in project PROJ
# Generated by jira.sh

fields:

  # Summary [REQUIRED] - Type: string
  summary: '{{PROMPT: Enter Summary}}'

  # Description [REQUIRED] - Type: string (multi-line)
  description: '{{PROMPT_MULTI: Enter Description}}'

  # Issue Type [REQUIRED] - Type: issuetype
  issuetype: {name: 'Story'}

  # Story Points - Type: number
  customfield_10016: '{{PROMPT: Enter Story Points}}'

  # Sprint - Type: array
  customfield_10020: '{{PROMPT: Enter Sprint (comma-separated)}}'

  # Labels - Type: array
  labels: '{{PROMPT: Enter Labels (comma-separated)}}'

  # Priority - Type: priority - Allowed: Highest, High, Medium, Low, Lowest
  priority: {name: '{{PROMPT: Enter priority}}'}
```

**Generated templates are interactive by default**, making them immediately reusable without editing. You can:
- Use them as-is for interactive ticket creation
- Change specific fields to static values (e.g., change `'{{PROMPT: Enter priority}}'` to `{name: 'High'}`)
- Mix interactive and static fields to suit your workflow

### 8. fetch-metadata - Fetch and Cache Metadata

Fetch and cache field metadata for a project and issue type:

```bash
jira_run ./jira.sh fetch-metadata <PROJECT> <ISSUE_TYPE> [options]
```

**Options:**
- `--refresh`: Force refresh the cache even if it exists

**Examples:**

```bash
# Fetch metadata for Stories in project PROJ
jira_run ./jira.sh fetch-metadata PROJ Story

# Force refresh cached metadata
jira_run ./jira.sh fetch-metadata PROJ Story --refresh
```

The metadata is cached in `~/.jira-cache/PROJECT-ISSUETYPE.json` for fast subsequent access.

## Workflow Examples

### Workflow 1: Create a Simple Task

The fastest way to create a ticket if your project doesn't require extra fields:

```bash
jira_run ./jira.sh create PROJ "Implement feature X" "Add support for feature X"
```

### Workflow 2: Generate and Use Interactive Template

When you need to create tickets with custom fields:

```bash
# Step 1: See what fields are required
jira_run ./jira.sh show-required PROJ Story

# Step 2: Generate an interactive template
jira_run ./jira.sh generate-template PROJ Story my-story.yml

# Step 3: Use the template immediately (it's interactive by default)
jira_run ./jira.sh create-from-template PROJ my-story.yml
# You'll be prompted for each field value

# Step 4: (Optional) Edit template to make some fields static
# Change any {{PROMPT:}} placeholders to static values as needed
# Then reuse the template
```

### Workflow 3: Build Template with Specific Fields

When you want to include only specific fields:

```bash
# Discover available fields for your project/issue type
jira_run ./jira.sh list-fields PROJ Story --filter "Story"
jira_run ./jira.sh list-fields PROJ Story --filter "Sprint"

# Generate template with multiple specific fields
jira_run ./jira.sh generate-template PROJ Story my-template.yml \
  --filter "Sprint" \
  --filter "Story Points" \
  --filter "Labels" \
  --filter "Assignee"

# Or build incrementally
jira_run ./jira.sh generate-template PROJ Story my-template.yml --required-fields
jira_run ./jira.sh generate-template PROJ Story my-template.yml \
  --filter "Sprint" \
  --filter "Story Points" \
  --update

# Use the interactive template
jira_run ./jira.sh create-from-template PROJ my-template.yml
```

### Workflow 4: Customize Interactive Template for Team Use

**Best practice for creating team-specific templates:**

Generated templates are interactive by default. Customize them by making common team fields static:

```bash
# Step 1: Generate initial template
jira_run ./jira.sh generate-template PROJ Story story-template.yml

# Step 2: Edit template - make team conventions static
nano story-template.yml
```

**Example: Change some fields from interactive to static:**

```yaml
fields:
  issuetype: {name: 'Story'}                                    # Static
  summary: '{{PROMPT: Enter story summary}}'                    # Interactive
  description: '{{PROMPT_MULTI: Enter story description}}'     # Interactive - multi-line
  labels: ['backend', 'api']                                    # Static - team labels
  priority: {name: 'Medium'}                                    # Static - default priority
  customfield_10016: '{{PROMPT: Enter story points}}'          # Interactive
  components: [{name: 'API'}]                                   # Static - component
```

**Step 3: Use the template repeatedly without editing files:**

```bash
# First ticket
jira_run ./jira.sh create-from-template PROJ story-template.yml
# Prompts for: summary, description, story points
# Creates: PROJ-101

# Second ticket (reuse same template)
jira_run ./jira.sh create-from-template PROJ story-template.yml
# Prompts again for: summary, description, story points
# Creates: PROJ-102

# Third ticket...
jira_run ./jira.sh create-from-template PROJ story-template.yml
```

**Benefits:**
- No file editing between tickets
- Consistent field values (labels, priority, components)
- Fast ticket creation
- Reduces errors from forgetting required fields

### Workflow 5: Bulk Update with Variations

When you need to update multiple tickets with some common changes and some variations:

```bash
# Step 1: Create an interactive update template
nano bulk-update.yml
```

```yaml
fields:
  labels: ['reviewed', 'team-alpha']  # Static - applied to all
  assignee: {name: '{{PROMPT: Enter assignee username}}'}  # Interactive
  comment: '{{INPUT: Enter update comment}}'  # Interactive
```

```bash
# Step 2: Update multiple tickets
jira_run ./jira.sh update PROJ-101 bulk-update.yml
# Prompts for: assignee, comment

jira_run ./jira.sh update PROJ-102 bulk-update.yml
# Prompts again for: assignee, comment

jira_run ./jira.sh update PROJ-103 bulk-update.yml
# And so on...
```

### Workflow 6: Discover Fields and Build Custom Template

When you need to explore available fields and build a custom template:

```bash
# Step 1: List fields available for your project/issue type
jira_run ./jira.sh list-fields PROJ Story

# Step 2: Generate template with required fields
jira_run ./jira.sh generate-template PROJ Story custom.yml --required-fields

# Step 3: Add specific fields incrementally
jira_run ./jira.sh generate-template PROJ Story custom.yml --filter "Sprint" --update
jira_run ./jira.sh generate-template PROJ Story custom.yml --filter "Points" --update
jira_run ./jira.sh generate-template PROJ Story custom.yml --filter "Priority" --update

# Step 4: Edit the template to customize values
nano custom.yml

# Step 5: Use the template
jira_run ./jira.sh create-from-template PROJ custom.yml
```

## Use Cases for Interactive Templates

### For Ticket Creation:
1. **Team Templates**: Pre-fill common fields (labels, priority, components) but prompt for summary/description
2. **Workflow Templates**: Static workflow fields, interactive story-specific fields
3. **Quick Creation**: Reduce repetitive typing while maintaining consistency
4. **Multi-Environment**: Same template, different values per environment

### For Ticket Updates:
1. **Bulk Updates with Variations**: Update many tickets with same labels but different statuses/assignees
2. **Workflow Transitions**: Pre-fill common workflow fields, prompt for ticket-specific notes
3. **Team Processes**: Standardize team fields while allowing per-ticket customization
4. **Quick Updates**: Update multiple tickets without editing files between each

## Troubleshooting

### Validation Errors

If you get validation errors about missing required fields:

```bash
# See what fields are required
jira_run ./jira.sh show-required PROJ Story

# Generate a template to ensure you have all fields
jira_run ./jira.sh generate-template PROJ Story complete.yml
```

### Cache Issues

If you're seeing stale metadata:

```bash
# Refresh the cache
jira_run ./jira.sh fetch-metadata PROJ Story --refresh
```

### API Errors

For debugging API issues:

```bash
# Use debug mode to see full API requests and responses
jira_run ./jira.sh --debug create PROJ "Test" "Description"
```

### Interactive Mode Issues

If interactive prompts aren't working:

```bash
# Check that you're in an interactive terminal
# Non-interactive environments (CI/CD, piped input) won't work with interactive templates

# Use --no-interactive to disable prompts (will error if placeholders found)
jira_run ./jira.sh create-from-template PROJ template.yml --no-interactive
```

## Environment & Dependencies

This solution is built to run in a Bash shell environment (Linux/macOS) and relies on:

- **`bash`**: The shell interpreter
- **`curl`**: Used to make REST API calls to Jira
- **`jq`**: A command-line JSON processor for parsing API responses
- **`yq`**: A command-line YAML processor for template files
- **`base64`**: For encoding credentials

The script will check for these dependencies on startup and report any missing tools.

## Related Documentation

- **[functions-jira.sh](functions-jira.md)**: Shared Jira API functions and interactive template processing
- **[functions.sh](../functions.sh)**: General utility functions (logging, validation)

## Migration from Old Scripts

If you were previously using `jira-create.sh` or `jira-soother.sh`, here are the command mappings:

**From jira-create.sh:**
- `jira-create.sh create-minimal` → `jira.sh create`
- `jira-create.sh create-from-template` → `jira.sh create-from-template` (unchanged)
- `jira-create.sh fetch-metadata` → `jira.sh fetch-metadata` (unchanged)
- `jira-create.sh show-required` → `jira.sh show-required` (unchanged)
- `jira-create.sh generate-template` → `jira.sh generate-template` (unchanged)

**From jira-soother.sh:**
- `jira-soother.sh find-fields` → `jira.sh list-fields`
- `jira-soother.sh apply-template` → `jira.sh update`

**Template Files:** All existing template files are 100% compatible and require no changes.
