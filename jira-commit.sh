#!/usr/bin/env bash
set -euo pipefail

#=============================================================================
### USAGE_START
#
# NAME
#   jira-commit.sh - Git Commit History Jira Key Auditor and Fixer
#
# SYNOPSIS
#   jira-commit.sh audit
#   jira-commit.sh amend <JIRA-KEY>
#   jira-commit.sh preview <JIRA-KEY>
#   jira-commit.sh verify
#   jira-commit.sh rollback [backup-branch]
#   jira-commit.sh help
#
# DESCRIPTION
#   This utility helps enforce Jira issue key standards in Git commit messages
#   on the current feature branch. It focuses on commits unique to the current
#   branch (i.e., commits since the base branch, typically 'main' or 'master').
#
#   The script includes automatic backup creation, preview mode, and rollback
#   capabilities to ensure safe history rewriting.
#
# COMMANDS
#
#   audit
#     Scans the subject line of all unique commits on the current branch.
#     It reports PASS if a Jira key (e.g., PROJ-123) is found, or FAIL otherwise.
#     Usage: ./jira-commit.sh audit
#
#   amend <JIRA-KEY>
#     Automatically rewrites commit messages to add Jira keys.
#     The provided <JIRA-KEY> (e.g., ABC-456) is injected according to:
#
#     1. Conventional Commits (e.g., feat: Subject)
#        -> Result: feat: ABC-456 Subject
#
#     2. Other formats (e.g., Subject without prefix)
#        -> Result: ABC-456 Subject
#
#     SAFETY FEATURES:
#     - Creates automatic backup branch before rewriting
#     - Shows preview of all changes
#     - Requires confirmation before proceeding
#     - Blocks execution on main/master branches
#     - Validates working directory is clean
#     - Warns if branch has been pushed to remote
#
#     WARNING: This command rewrites history using 'git filter-branch'.
#              After running, you'll need to force push: git push --force-with-lease
#
#     Usage: ./jira-commit.sh amend PROJ-123
#
#   preview <JIRA-KEY>
#     Shows what commit messages will look like after adding the Jira key,
#     without actually modifying anything. Useful for checking before running amend.
#     Usage: ./jira-commit.sh preview PROJ-123
#
#   verify
#     Verifies that all commits on the current branch have Jira keys.
#     Displays a checklist with ✓ for commits that pass and ✗ for those that fail.
#     Useful after running amend to confirm all commits were updated.
#     Usage: ./jira-commit.sh verify
#
#   rollback [backup-branch]
#     Restores your branch to a backup. If no backup branch is specified,
#     lists all available backup branches. Useful if amend produces unexpected results.
#     Usage: ./jira-commit.sh rollback
#     Usage: ./jira-commit.sh rollback feature/my-feature_backup_20250120-143022
#
#   --debug
#     Enable debug mode with verbose output. Can be combined with any command.
#     Usage: ./jira-commit.sh audit --debug
#
# EXAMPLES
#
#   # Check which commits are missing Jira keys
#   ./jira-commit.sh audit
#
#   # Preview changes before applying
#   ./jira-commit.sh preview PROJ-123
#
#   # Add Jira key to all commits (with automatic backup)
#   ./jira-commit.sh amend PROJ-123
#
#   # Verify all commits now have Jira keys
#   ./jira-commit.sh verify
#
#   # If something went wrong, rollback
#   ./jira-commit.sh rollback
#
#   # Force push the changes (after verifying)
#   git push --force-with-lease
#
# SAFETY NOTES
#
#   - Always create a backup before rewriting history (done automatically by amend)
#   - Review changes with verify before force pushing
#   - Use --force-with-lease instead of --force when pushing
#   - Never rewrite history that's been shared without team coordination
#   - Backup branches are named: <branch-name>_backup_<timestamp>
#   - Compatible with git-flow branch naming (feature/, bugfix/, hotfix/, etc.)
#
### USAGE_END
#=============================================================================

# Source reusable functions
# shellcheck source=functions.sh
source "$(dirname "$0")/functions.sh"

# --- Constants ---
readonly JIRA_REGEX='[A-Z]{2,}-[0-9]+'
readonly CONVENTIONAL_REGEX='^([a-z]+)(\(.+\))?: (.*)'
readonly RESULT_COL_WIDTH=12
readonly RESULT_TEXT_WIDTH=4

# --- Variables ---
# Git repository context information
LOG_RANGE=""
STATUS_MESSAGE=""
BRANCH_NAME=""

# --- Helper Functions ---

#-----------------------------------------------------------------------------
# Function: has_jira_key
# Description: Checks if a commit subject contains a Jira key
# Arguments: $1 - commit subject line
# Returns: 0 if Jira key found, 1 if not found
#-----------------------------------------------------------------------------
has_jira_key() {
	local subject="$1"
	[[ "$subject" =~ $JIRA_REGEX ]]
}

#-----------------------------------------------------------------------------
# Function: validate_git_state
# Description: Validates that we're in a git repository and ready for operations
# Arguments: $1 - operation type ("audit" or "amend")
# Returns: 0 on success, 1 on failure
#-----------------------------------------------------------------------------
validate_git_state() {
	local operation="${1:-audit}"

	# Check if we're in a git repository
	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		log_error "Not a git repository. Please run this script from within a git repository."
		return 1
	fi

	# Check for ongoing rebase
	local git_dir
	git_dir=$(git rev-parse --git-dir 2>/dev/null)
	if [[ -d "$git_dir/rebase-merge" ]] || [[ -d "$git_dir/rebase-apply" ]]; then
		log_error "A rebase is already in progress."
		log_error "Please complete it with 'git rebase --continue' or abort it with 'git rebase --abort'"
		return 1
	fi

	# For amend operations, check if working directory is clean
	if [[ "$operation" == "amend" ]]; then
		if ! git diff-index --quiet HEAD -- 2>/dev/null; then
			log_error "Working directory has uncommitted changes."
			log_error "Please commit or stash them before rewriting history."
			log_error "  git stash push -m 'Temporary stash before jira-commit amend'"
			return 1
		fi

		# Check for staged changes
		if ! git diff-index --quiet --cached HEAD -- 2>/dev/null; then
			log_error "There are staged changes in the index."
			log_error "Please commit or reset them before rewriting history."
			return 1
		fi
	fi

	return 0
}

#-----------------------------------------------------------------------------
# Function: check_branch_safety
# Description: Checks if it's safe to rewrite history on the current branch
# Returns: 0 on success, 1 if operation should be blocked
#-----------------------------------------------------------------------------
check_branch_safety() {
	local branch_name
	branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

	# Block rewrites on main/master branches
	if [[ "$branch_name" == "main" ]] || [[ "$branch_name" == "master" ]]; then
		log_error "Cannot rewrite history on protected branch '$branch_name'."
		log_error "Please create a feature branch first:"
		log_error "  git checkout -b feature/my-feature"
		return 1
	fi

	# Check if branch has upstream tracking (has been pushed)
	if git rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
		local upstream
		upstream=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
		log_warning "Branch '$branch_name' tracks remote '$upstream'."
		log_warning "After rewriting history, you'll need to force push:"
		log_warning "  git push --force-with-lease origin $branch_name"
		echo ""
	fi

	return 0
}

#-----------------------------------------------------------------------------
# Function: create_backup_branch
# Description: Creates a backup branch before rewriting history
# Returns: 0 on success, 1 on failure
# Outputs: The backup branch name
#-----------------------------------------------------------------------------
create_backup_branch() {
	local branch_name
	branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

	local timestamp
	timestamp=$(date +%Y%m%d-%H%M%S)

	local backup_branch="${branch_name}_backup_${timestamp}"

	log_info "Creating backup branch: $backup_branch"

	if git branch "$backup_branch" >/dev/null 2>&1; then
		log_info "Backup created successfully. To restore:"
		log_info "  git reset --hard $backup_branch"
		echo "$backup_branch"
		return 0
	else
		log_error "Failed to create backup branch"
		return 1
	fi
}

# Function to extract and display the usage block
show_help() {
	# Extracts the content between the USAGE_START and USAGE_END markers.
	# We strip the leading '#' and ONLY the first space to preserve relative indentation.
	# The 'q' command ensures parsing stops immediately after USAGE_END.
	sed -n '/### USAGE_START/,/### USAGE_END/{ /### USAGE_START/d; /### USAGE_END/q; s/^#//; s/^ //; p; }' "$0"
}

# Function to print the simplified header
print_header() {
	local branch_name="$1"
	local status_message="$2"

	log_info "JIRA COMMIT AUDIT: $branch_name"
	log_info "$status_message"
	echo ""
	printf "%-8s %-12s %s\n" "HASH" "RESULT" "SUBJECT"
	echo "-------------------------------------------------------"
}

# Function to determine the Git log range based on existing branches
get_log_range() {
	local base_commit=""

	# Check for 'main' branch existence
	if git rev-parse --verify main >/dev/null 2>&1; then
		base_commit="main"
	# Check for 'master' branch existence
	elif git rev-parse --verify master >/dev/null 2>&1; then
		base_commit="master"
	fi

	local branch_name
	branch_name=$(git rev-parse --abbrev-ref HEAD)

	if [[ -n "$base_commit" ]]; then
		LOG_RANGE="$base_commit..HEAD"
		STATUS_MESSAGE="Checking unique commits on this branch (Range: $LOG_RANGE) for a valid Jira Key."
	else
		LOG_RANGE="HEAD"
		STATUS_MESSAGE="Could not find 'main' or 'master' branch. Checking all commits on '$branch_name'."
	fi

	# Update exported variables
	BRANCH_NAME="$branch_name"
}

# Function to run the audit and print the results
run_audit() {
	# Calculate padding once
	local pad_width
	pad_width=$((RESULT_COL_WIDTH - RESULT_TEXT_WIDTH))

	# Use the exported LOG_RANGE and iterate over commits
	# Format: %h (short hash), %s (subject) separated by a tab
	git log --no-merges --pretty=format:"%h%x09%s" "$LOG_RANGE" | while IFS=$'\t' read -r hash subject; do

		local color_code result_text

		# Determine result and color using helper function
		if has_jira_key "$subject"; then
			color_code="$GREEN"
			result_text="PASS"
		else
			color_code="$RED"
			result_text="FAIL"
		fi

		# Print HASH (8 chars wide)
		printf "%-8s" "$hash"

		# Print Colored Result (Manually aligned for perfect column width)
		# 1. Start color code. 2. Print result text (4 chars). 3. Reset color.
		# 4. Print padding spaces using %*s (width defined by $pad_width, string is empty).
		printf " ${color_code}%s${NC}%*s" "$result_text" $pad_width ""

		# Print Subject
		printf " %s\n" "$subject"

	done
}

#-----------------------------------------------------------------------------
# Function: verify_commits
# Description: Verifies that all commits on the current branch have Jira keys
# Returns: 0 if all commits pass, 1 if any fail
#-----------------------------------------------------------------------------
verify_commits() {
	local failed_count=0
	local total_count=0

	log_info "Verifying Jira keys in commits on range: $LOG_RANGE"
	echo ""

	# Check each commit
	while IFS=$'\t' read -r hash subject; do
		total_count=$((total_count + 1))
		if ! has_jira_key "$subject"; then
			failed_count=$((failed_count + 1))
			printf "${RED}✗${NC} %-8s %s\n" "$hash" "$subject"
		else
			printf "${GREEN}✓${NC} %-8s %s\n" "$hash" "$subject"
		fi
	done < <(git log --no-merges --pretty=format:"%h%x09%s" "$LOG_RANGE")

	echo ""
	if [[ $failed_count -eq 0 ]]; then
		log_info "✓ All $total_count commit(s) have Jira keys"
		return 0
	else
		log_error "✗ $failed_count out of $total_count commit(s) are missing Jira keys"
		return 1
	fi
}

#-----------------------------------------------------------------------------
# Function: rollback_to_backup
# Description: Rolls back to a backup branch
# Arguments: $1 - backup branch name (optional, will list if not provided)
# Returns: 0 on success, 1 on failure
#-----------------------------------------------------------------------------
rollback_to_backup() {
	local backup_branch="$1"

	# If no backup branch specified, list available backups
	if [[ -z "$backup_branch" ]]; then
		log_info "Available backup branches:"
		echo ""

		local found_backups=false
		while read -r branch; do
			found_backups=true
			# Show branch with creation date
			local branch_date
			branch_date=$(git log -1 --format=%ci "$branch" 2>/dev/null | cut -d' ' -f1,2)
			printf "  ${CYAN}%s${NC} (created: %s)\n" "$branch" "$branch_date"
		done < <(git branch --list '*_backup_*' | sed 's/^[* ]*//')

		if [[ "$found_backups" == "false" ]]; then
			log_warning "No backup branches found."
			return 1
		fi

		echo ""
		log_info "To rollback, run: $0 rollback <backup-branch-name>"
		return 0
	fi

	# Verify the backup branch exists
	if ! git rev-parse --verify "$backup_branch" >/dev/null 2>&1; then
		log_error "Backup branch '$backup_branch' does not exist."
		return 1
	fi

	# Get current branch name
	local current_branch
	current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

	# Confirm the rollback
	log_warning "This will reset your current branch ($current_branch) to $backup_branch."
	log_warning "Any commits made after the backup will be lost!"
	echo -n "Proceed with rollback? [y/N] "
	read -r response

	if [[ ! "$response" =~ ^[Yy]$ ]]; then
		log_info "Rollback cancelled."
		return 0
	fi

	# Perform the rollback
	log_info "Rolling back to $backup_branch..."
	if git reset --hard "$backup_branch"; then
		log_info "✓ Successfully rolled back to $backup_branch"
		log_info ""
		log_info "The backup branch still exists. To remove it:"
		log_info "  git branch -D $backup_branch"
		return 0
	else
		log_error "Rollback failed"
		return 1
	fi
}

#-----------------------------------------------------------------------------
# Function: preview_commit_changes
# Description: Shows what commit messages will look like after adding Jira keys
# Arguments: $1 - jira_key (e.g., ABC-123)
# Returns: 0 on success, 1 on failure
#-----------------------------------------------------------------------------
preview_commit_changes() {
	local jira_key="$1"

	# Validate Jira key format
	if ! [[ "$jira_key" =~ $JIRA_REGEX ]]; then
		log_error "'$jira_key' is not a valid Jira key (e.g., ABC-123)."
		return 1
	fi

	log_info "PREVIEW: Commit message changes with Jira key: $jira_key"
	echo ""

	local changes_found=false

	# Iterate through commits and show before/after
	while IFS=$'\t' read -r hash subject; do
		# Check if this commit needs updating
		if ! has_jira_key "$subject"; then
			changes_found=true

			# Calculate new subject line using the same logic as the filter
			local new_subject
			if [[ "$subject" =~ $CONVENTIONAL_REGEX ]]; then
				# Conventional Commit format
				local type="${BASH_REMATCH[1]}"
				local scope="${BASH_REMATCH[2]}"
				local rest="${BASH_REMATCH[3]}"
				new_subject="${type}${scope}: $jira_key ${rest}"
			else
				# Other format: prepend
				new_subject="$jira_key $subject"
			fi

			# Display the change
			printf "${YELLOW}%-8s${NC}\n" "$hash"
			printf "  ${RED}Before:${NC} %s\n" "$subject"
			printf "  ${GREEN}After:${NC}  %s\n" "$new_subject"
			echo ""
		fi
	done < <(git log --no-merges --pretty=format:"%h%x09%s" "$LOG_RANGE")

	if [[ "$changes_found" == "false" ]]; then
		log_info "No commits need updating - all commits already have Jira keys."
		return 0
	fi

	return 0
}

#-----------------------------------------------------------------------------
# Function: amend_commits
# Description: Automatically rewrites commit messages to add Jira keys using
#              git filter-branch
# Arguments: $1 - jira_key (e.g., ABC-123)
# Returns: 0 on success, 1 on failure
#-----------------------------------------------------------------------------
amend_commits() {
	local jira_key="$1"

	# Validate Jira key format
	if ! [[ "$jira_key" =~ $JIRA_REGEX ]]; then
		log_error "'$jira_key' is not a valid Jira key (e.g., ABC-123)."
		return 1
	fi

	# 1. Determine the commits that FAIL the audit and need rewriting
	local failed_commits_count=0

	# Get all unique commits that FAIL the audit (those without a Jira key)
	while IFS=$'\t' read -r hash subject; do
		if ! has_jira_key "$subject"; then
			failed_commits_count=$((failed_commits_count + 1))
		fi
	done < <(git log --no-merges --pretty=format:"%h%x09%s" "$LOG_RANGE")

	if [[ "$failed_commits_count" -eq 0 ]]; then
		log_info "No commits failed the audit (0 commits to amend)."
		return 0
	fi

	# 2. Extract the base commit for the filter-branch operation
	local base_commit_hash
	if [[ "$LOG_RANGE" =~ ^(.+)\.\..* ]]; then
		base_commit_hash="${BASH_REMATCH[1]}"
	elif [[ "$LOG_RANGE" == "HEAD" ]]; then
		log_error "Cannot rewrite commits - no base branch found."
		log_error "This script requires a base branch (main or master) to determine which commits to rewrite."
		return 1
	else
		log_error "Unexpected LOG_RANGE format: $LOG_RANGE"
		return 1
	fi

	log_warning "\n--- AMENDMENT SUMMARY ---"
	log_info "Jira Key: $jira_key"
	log_info "Base Commit: $base_commit_hash"
	log_info "Commits to be amended: $failed_commits_count"
	echo ""

	# Show preview of changes
	preview_commit_changes "$jira_key"
	echo ""

	# Ask for confirmation
	log_warning "This will rewrite commit history!"
	echo -n "Proceed with rewriting $failed_commits_count commit(s)? [y/N] "
	read -r response

	if [[ ! "$response" =~ ^[Yy]$ ]]; then
		log_info "Aborted by user."
		return 0
	fi

	echo ""

	# Create the message filter script that will rewrite commit messages
	local filter_script
	filter_script=$(mktemp) || {
		log_error "Failed to create temporary filter script"
		return 1
	}

	# Ensure cleanup on exit
	trap "rm -f '$filter_script'" RETURN

	# Write the filter script that processes each commit message
	cat > "$filter_script" << 'FILTER_SCRIPT_EOF'
#!/bin/bash

# Define regex patterns
JIRA_REGEX='[A-Z]{2,}-[0-9]+'
CONVENTIONAL_REGEX='^([a-z]+)(\(.+\))?: (.*)'

# Read the commit message from stdin
commit_msg=$(cat)

# Extract just the subject line (first line)
subject_line=$(echo "$commit_msg" | head -n 1)

# Check if subject already has a Jira key
if [[ "$subject_line" =~ $JIRA_REGEX ]]; then
	# Already has Jira key, pass through unchanged
	echo "$commit_msg"
else
	# No Jira key found, rewrite the subject line

	# Check for Conventional Commit format: type(scope): subject
	if [[ "$subject_line" =~ $CONVENTIONAL_REGEX ]]; then
		# Conventional Commit: insert Jira key after the type/scope
		type="${BASH_REMATCH[1]}"
		scope="${BASH_REMATCH[2]}"
		rest="${BASH_REMATCH[3]}"
		new_subject="${type}${scope}: JIRA_KEY_PLACEHOLDER ${rest}"
	else
		# Other format: prepend Jira key
		new_subject="JIRA_KEY_PLACEHOLDER ${subject_line}"
	fi

	# Output the new subject line followed by the rest of the commit message
	echo "$new_subject"
	echo "$commit_msg" | tail -n +2
fi
FILTER_SCRIPT_EOF

	# Replace the placeholder with the actual Jira key
	sed -i "s/JIRA_KEY_PLACEHOLDER/$jira_key/g" "$filter_script"
	chmod +x "$filter_script"

	# 3. Run git filter-branch to rewrite commit messages
	log_info "Rewriting commit history using git filter-branch..."
	echo ""

	# Note: filter-branch requires FILTER_BRANCH_SQUELCH_WARNING or shows deprecation warning
	FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch \
		--msg-filter "$filter_script" \
		--force \
		-- "$base_commit_hash..HEAD"

	local filter_exit_code=$?

	if [[ $filter_exit_code -eq 0 ]]; then
		echo ""
		log_info "✓ Successfully rewrote $failed_commits_count commit(s)"
		echo ""
		log_info "Next steps:"
		log_info "  1. Review the changes: git log $base_commit_hash..HEAD"
		log_info "  2. If satisfied, force push: git push --force-with-lease"
		log_info "  3. If needed, rollback to backup branch created earlier"
		return 0
	else
		echo ""
		log_error "git filter-branch failed with exit code $filter_exit_code"
		log_error "Your repository may be in an inconsistent state."
		log_error "To recover, reset to the backup branch created earlier."
		return 1
	fi
}

# Main function (entry point)
main() {
	# Handle debug flag (can be anywhere in arguments)
	if [[ "$*" =~ --debug ]]; then
		LOG_LEVEL="DEBUG"
		set -x  # Enable bash debug output
		log_debug "Debug mode enabled"
	fi

	# Parse main commands: audit, amend, or help
	case "$1" in
	audit)
		# Validate git repository state
		validate_git_state "audit" || exit 1

		get_log_range
		print_header "$BRANCH_NAME" "$STATUS_MESSAGE"
		run_audit
		;;
	amend)
		if [[ -z "$2" ]]; then
			log_error "Missing Jira key. Usage: $0 amend <JIRA-XXX>"
			exit 1
		fi

		# Validate git repository state for amend operation
		validate_git_state "amend" || exit 1

		# Check if it's safe to rewrite history on this branch
		check_branch_safety || exit 1

		# Create backup branch before proceeding
		local backup_branch
		backup_branch=$(create_backup_branch) || exit 1
		echo ""

		get_log_range
		amend_commits "$2"
		;;
	preview)
		if [[ -z "$2" ]]; then
			log_error "Missing Jira key. Usage: $0 preview <JIRA-XXX>"
			exit 1
		fi

		# Validate git repository state
		validate_git_state "audit" || exit 1

		get_log_range
		preview_commit_changes "$2"
		;;
	verify)
		# Validate git repository state
		validate_git_state "audit" || exit 1

		get_log_range
		verify_commits
		;;
	rollback)
		# Validate git repository state
		validate_git_state "audit" || exit 1

		rollback_to_backup "$2"
		;;
	help)
		show_help
		;;
	*)
		log_error "Invalid command."
		echo ""
		show_help
		exit 1
		;;
	esac
}

# Execute main function only when script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
