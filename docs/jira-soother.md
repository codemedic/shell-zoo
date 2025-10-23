# Jira Soother

This project provides a Bash script, `jira-soother.sh`, to programmatically apply project-specific templates to a Jira Cloud ticket. It is designed to counteract useless default values by letting you define and apply a set of common fields for your project or team.

## Environment & Dependencies

This solution is built to run in a Bash shell environment (Linux/macOS) and relies on a few key tools:

- **`bash`**: The shell interpreter.
- **`curl`**: Used to make the REST API calls to the Jira Cloud service.
- **`jq`**: A command-line JSON processor used to parse API responses and validate the configuration file.
- **`base64`**: For encoding credentials.

## Solution Overview

The solution consists of two main components:

1. **`jira-soother.sh`**: A script that connects to your Jira instance and can either:
   - **`find-fields`**: Print a list of all available fields (both standard and custom). It shows the human-readable `name`, the internal `id` (which is required by the API), and any "canned values" (e.g., dropdown options like "High", "Medium", "Low").
   - **`apply-template`**: Update a ticket. It takes two arguments: the Jira ticket key (e.g., `PROJECT-123`) and the path to a YAML configuration file. It sends a `PUT` request to the Jira API to update the ticket.
2. **`template-example.yml`**: A YAML file that serves as a template for the update. You edit this file to define _only_ the fields you wish to change and the values you want to set. This separates the update logic from the data itself, making it easy to manage different templates.

## How to Use

### Step 1: Set Up Environment Variables

The script relies on the following environment variables for Jira authentication:

- `jira_base_url`: Your Jira instance URL (e.g., `https://company.atlassian.net`).
- `jira_user`: Your Jira username (e.g., `user@company.com`).
- `jira_password`: Your Jira API token.

It is recommended to use a wrapper function like `jira_run` to set these variables securely.

**For Linux (with KDE Wallet):**

If you use a password manager like `kwallet`, you could create this function in your `.bashrc` or `.zshrc`:

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

On macOS, you can use the built-in Keychain. First, add your API token to Keychain Access with this command:

```bash
security add-generic-password -a 'user@company.com' -s 'jira-cloud-token' -w 'YOUR_JIRA_API_TOKEN'
```

Then, create this function in your `.zshrc` or `.bash_profile`:

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

This function makes it easy to run the script without exposing your credentials on the command line: `jira_run ./jira-soother.sh ...`.

### Step 2: Find Field IDs

Before you can update fields, you need their internal IDs.

1. Make the script executable: `chmod +x jira-soother.sh`
2. Run the `find-fields` subcommand and search for the fields you care about:

```bash
jira_run ./jira-soother.sh find-fields | grep -i "Story Points"
# Output might be: { "id": "customfield_10028", "name": "Story Points", ... }
```

### Step 3: Prepare Your Config File

1. Copy or rename `template-example.yml` (e.g., `bug_template.yml`).
2. Edit the file, using the field IDs you found in Step 2.
3. Set the values you want to apply. Refer to `template-example.yml` for examples of simple text, labels, dropdowns (`priority`), and user fields (`assignee`).

### Step 4: Apply the Template

Run the `apply-template` subcommand, passing the ticket key and your config file path:

```bash
jira_run ./jira-soother.sh apply-template PROJECT-123 bug_template.yml
```

On success, you will see:

```text
Successfully updated ticket PROJECT-123!
View it here: https://company.atlassian.net/browse/PROJECT-123
```
