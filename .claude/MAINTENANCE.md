# Maintenance Guidelines for Shell Zoo

This document provides guidelines for maintaining consistency across scripts and documentation in the Shell Zoo project.

## 🎯 Core Principles

1. **DRY (Don't Repeat Yourself)**: Common functionality should be in shared libraries
2. **Consistency**: All scripts should follow the same patterns and conventions
3. **Documentation**: Every change to code requires corresponding documentation updates
4. **Testing**: Scripts should be tested after changes

## 📁 Project Structure

```
shell-zoo/
├── README.md                    # Main project documentation
├── functions.sh                 # General-purpose shared functions
├── functions-jira.sh            # Jira-specific shared functions
├── jira-create.sh              # Jira ticket creation script
├── jira-soother.sh             # Jira ticket update script
├── docs/
│   ├── jira-create.md          # jira-create.sh documentation
│   ├── jira-soother.md         # jira-soother.sh documentation
│   ├── functions-jira.md       # functions-jira.sh API reference
│   └── ...
└── .claude/
    └── MAINTENANCE.md          # This file
```

## 🔄 When Making Changes

### 1. Modifying Shared Functions (`functions.sh` or `functions-jira.sh`)

**Always update:**
- [ ] The function implementation in the library file
- [ ] The corresponding documentation in `docs/functions-jira.md` (for Jira functions)
- [ ] Any scripts that call the modified function (if signature changed)
- [ ] Examples in the documentation showing the new usage

**Checklist:**
1. Modify the function in the library file
2. Update the function reference section in docs
3. Update code examples that use the function
4. Search for all usages: `grep -r "function_name" *.sh`
5. Test all affected scripts

### 2. Modifying Scripts (`jira-create.sh` or `jira-soother.sh`)

**Always update:**
- [ ] The script file itself
- [ ] The script's documentation file in `docs/`
- [ ] The `--help` output in the script (usage() function)
- [ ] `README.md` if the change affects the script's description

**Checklist:**
1. Make code changes in the script
2. Update the `usage()` function if command-line interface changed
3. Update the corresponding doc file in `docs/`
4. Test the script with `--help` flag
5. Test all subcommands
6. Update README.md if feature list changed

### 3. Adding New Subcommands

**Files to update:**
1. **Script file** (`jira-create.sh` or `jira-soother.sh`):
   - Add new function for the subcommand
   - Add case in main() function
   - Update usage() function

2. **Script documentation** (`docs/jira-create.md` or `docs/jira-soother.md`):
   - Add subcommand to "Solution Overview"
   - Add detailed section with syntax, options, examples
   - Add workflow examples if applicable
   - Update list of subcommands in help section

3. **README.md**:
   - Update feature description if needed

**Template for new subcommand:**
```bash
# In script:
subcommand_name() {
    if [ "$#" -lt 1 ]; then
        log_error "Usage: ./script.sh subcommand-name <ARG> [options]"
        exit 1
    fi

    local required_arg="$1"
    shift

    # Parse options
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --option)
                # Handle option
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Implementation
    log_info "Doing something..."
}

# In main():
case "$subcommand" in
    # ... existing cases ...
    subcommand-name)
        subcommand_name "$@"
        ;;
esac

# In usage():
Subcommands:
  # ... existing subcommands ...
  subcommand-name    Brief description

'subcommand-name' Subcommand Usage:
  ./script.sh subcommand-name <ARG> [--option]

  <ARG>         Description
  --option      Description
```

### 4. Adding New Global Options

**Files to update:**
1. **Both scripts**: Add option parsing in main() function
2. **Both docs**: Add option to "Global Options" section
3. **functions-jira.sh**: Update `parse_global_options()` if applicable

**Ensure consistency:**
- Both `jira-create.sh` and `jira-soother.sh` must support the same global options
- Global options must be documented identically in both doc files

### 5. Modifying API Functions

**When changing `jira_api_get()`, `jira_api_post()`, or `jira_api_put()`:**

1. **Update `functions-jira.sh`**:
   - Modify the function
   - Update internal comments

2. **Update `docs/functions-jira.md`**:
   - Update function signature
   - Update parameter descriptions
   - Update global variables section
   - Update examples
   - Update "Complete Example" section if affected

3. **Test all scripts**:
   - Test `jira-create.sh` with all subcommands
   - Test `jira-soother.sh` with all subcommands
   - Use `--debug` to verify API calls work correctly

4. **Verify error handling**:
   - Test with invalid credentials
   - Test with non-existent resources
   - Ensure error messages are clear

## 📋 Consistency Checklist

### Command-Line Interface Consistency

Both `jira-create.sh` and `jira-soother.sh` must maintain:

- [ ] Same global options (--help, --log-level, --debug, --verbose, --quiet)
- [ ] Same option parsing order (global options → subcommand → subcommand options)
- [ ] Same help behavior (works without environment variables)
- [ ] Same validation order (help → environment → dependencies → subcommand)
- [ ] Same error message format
- [ ] Same logging level behavior

### Code Style Consistency

- [ ] Use `set -euo pipefail` at the top of all scripts
- [ ] Source libraries with shellcheck directives
- [ ] Use `log_*` functions for all output (not echo for errors)
- [ ] Use common validation functions from libraries
- [ ] Use common API functions from `functions-jira.sh`
- [ ] Validate environment after help check
- [ ] Use consistent variable naming (snake_case)
- [ ] Use consistent function naming (snake_case with descriptive names)

### Documentation Consistency

- [ ] All docs follow same structure:
  1. Title and brief intro
  2. Solution Overview
  3. How to Use (with global options)
  4. Environment Setup
  5. Detailed features/subcommands
  6. Workflow examples
  7. Troubleshooting (if applicable)
  8. Dependencies
  9. Related documentation

- [ ] All code examples are tested and work
- [ ] All examples use `jira_run` wrapper for credentials
- [ ] Cross-references use relative links: `[text](file.md)`
- [ ] Command syntax uses consistent formatting: ` ```bash ... ``` `

## 🧪 Testing Checklist

Before committing changes:

### Script Testing
- [ ] Run `shellcheck` on all modified scripts
- [ ] Test `--help` without environment variables (should work)
- [ ] Test with `--debug` to verify logging
- [ ] Test with `--quiet` to verify minimal output
- [ ] Test all subcommands with valid inputs
- [ ] Test with invalid inputs (should show clear errors)
- [ ] Test with missing required arguments (should show usage)

### Documentation Testing
- [ ] Verify all links work (internal references)
- [ ] Verify all code examples have correct syntax
- [ ] Check that examples match current script behavior
- [ ] Verify help output matches documented options

### Integration Testing
- [ ] Test scripts with actual Jira instance (if available)
- [ ] Test error scenarios (invalid credentials, missing fields)
- [ ] Verify error messages are user-friendly

## 🔍 Common Patterns

### Error Handling Pattern
```bash
# In scripts - let common functions handle errors
if ! jira_api_get "/rest/api/2/field"; then
    exit 1  # Error already logged by jira_api_get
fi

# Access response
echo "${jira_response_body}" | jq '.[]'
```

### Validation Pattern
```bash
# In scripts
if ! validate_yaml_file "${yaml_file}"; then
    exit 1  # Error already logged
fi

# Continue with validated file
yaml_content=$(yq -o=json '.' "${yaml_file}")
```

### Option Parsing Pattern
```bash
# In subcommand functions
local option_value=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --option)
            if [ -z "$2" ]; then
                log_error "Error: --option requires a value."
                return 1
            fi
            option_value="$2"
            shift 2
            ;;
        *)
            log_error "Error: Unknown option '$1'"
            echo "Usage: ..."
            return 1
            ;;
    esac
done
```

## 📝 Documentation Templates

### Adding Example to Documentation

When adding examples to documentation, follow this structure:

**Template:**
- Section heading: `### Example: Description`
- Brief explanation paragraph
- Code block with command (use bash syntax highlighting)
- Output section showing expected results
- Explanation bullet points

**Example structure:**
```
### Example: Creating a Simple Task

This example shows how to create a basic task ticket.

Command:
  jira_run ./script.sh subcommand ARG --option VALUE

Output:
  Expected output here

Explanation:
- What happened in the command
- Why this is useful
```

### Adding Workflow to Documentation

When adding multi-step workflows, follow this structure:

**Template:**
- Section heading: `### Workflow N: Workflow Name`
- Brief description of when to use this workflow
- Code block with all steps (using bash comments)
- Explanation of the workflow's usefulness

**Example structure:**
```
### Workflow 1: Create Ticket from Template

Use this when you need to create tickets with custom fields.

Steps:
  # Step 1: Generate template
  jira_run ./script.sh generate-template PROJ Story template.yml

  # Step 2: Edit the template
  nano template.yml

  # Step 3: Create the ticket
  jira_run ./script.sh create-from-template PROJ template.yml

This workflow is useful when you need consistent ticket creation.
```

## 🚨 Breaking Changes

If making a breaking change (changes that affect existing users):

1. **Document the change in your session summary**:
   - Clearly mark as "BREAKING CHANGE" in the summary
   - Explain what changed and why
   - Provide migration path for users
   - Include before/after examples

2. **Update all affected documentation**:
   - Update examples that no longer work
   - Add deprecation notices if keeping old behavior temporarily
   - Update README.md

3. **Consider backward compatibility**:
   - Can the old usage still work with a warning?
   - Can you provide a migration script?
   - Should you version the scripts?

4. **Include in commit message**:
   - Mark breaking changes clearly in the git commit message
   - Use conventional commit format: `feat!: description` or `BREAKING CHANGE:` in body

## 🔗 Quick Reference

### Files Always Modified Together

| When you change... | Also update... |
|-------------------|----------------|
| `functions-jira.sh` function | `docs/functions-jira.md` API reference |
| `jira-create.sh` subcommand | `docs/jira-create.md` subcommand section |
| `jira-soother.sh` subcommand | `docs/jira-soother.md` subcommand section |
| Script global options | Both script docs + help output |
| Script description | `README.md` + script doc file |
| Shared function signature | All scripts using it + docs |

### Search Commands for Impact Analysis

```bash
# Find all usages of a function
grep -rn "function_name" *.sh

# Find all references in documentation
grep -rn "function_name" docs/

# Find all scripts using a specific API endpoint
grep -rn "/rest/api/2/endpoint" *.sh

# Check for consistency across scripts
diff <(grep "^# Global Options:" docs/jira-create.md) \
     <(grep "^# Global Options:" docs/jira-soother.md)
```

## 🎓 For Claude Code / AI Assistants

When asked to modify these scripts:

1. **Always read this file first** to understand maintenance requirements
2. **Check consistency** between jira-create.sh and jira-soother.sh
3. **Update documentation** in the same change as code updates
4. **Follow the patterns** documented here
5. **Test help output** works without environment variables
6. **Verify global options** are consistent across both scripts
7. **Use the templates** provided in this file
8. **Run the checklists** before considering work complete

### Quick Checklist for Changes

- [ ] Read MAINTENANCE.md (this file)
- [ ] Identify all files that need updates
- [ ] Make code changes
- [ ] Update help/usage output
- [ ] Update corresponding documentation
- [ ] Update README.md if needed
- [ ] Check consistency with related scripts
- [ ] Test the changes
- [ ] Verify examples in docs still work

### End of Session Summary

When the user asks to summarize changes (or at the end of a session), provide:

1. **Summary of Changes**:
   - List all files modified/created
   - Describe what changed in each file
   - Explain the purpose of the changes

2. **Breaking Changes** (if any):
   - Clearly mark any breaking changes
   - Explain what broke and why
   - Provide migration instructions with examples
   - Show before/after usage patterns

3. **New Features** (if any):
   - List new capabilities added
   - Provide usage examples
   - Link to relevant documentation

4. **Documentation Updates**:
   - List all documentation changes
   - Highlight any new docs created

5. **Testing Recommendations**:
   - Suggest what the user should test
   - Provide test commands if applicable

6. **Suggested Commit Message**:
   - Provide a clear, descriptive commit message
   - Follow conventional commit format
   - Include all affected files

**Example Summary Template:**

```
## Session Summary

### Changes Made
- Modified: script.sh - Added new feature X
- Updated: docs/script.md - Documented feature X
- Created: new-file.sh - New script for Y

### Breaking Changes
⚠️ BREAKING CHANGE: Feature Z now requires --option flag

Before:
  ./script.sh subcommand arg

After:
  ./script.sh subcommand arg --option value

Migration: Update all calls to include --option flag.

### New Features
- Feature X: Does something useful
  Usage: ./script.sh new-subcommand

### Documentation
- Updated script.md with new examples
- Added workflow section for common use case

### Testing
Please test:
  ./script.sh --help
  ./script.sh new-subcommand arg

### Suggested Commit
git commit -m "feat: Add feature X

- Implement new subcommand for X
- Update documentation with examples
- Add tests for new functionality

BREAKING CHANGE: Feature Z requires --option flag"
```

## 📚 Additional Resources

- **Shellcheck**: Use `shellcheck script.sh` to catch common issues
- **Testing**: Always test with actual Jira instance when possible
- **Git**: Use descriptive commit messages mentioning both code and doc changes

---

**Remember**: Code and documentation must always stay in sync. If you change one, you must change the other!
