# jira-commit.sh

Git commit history auditor and fixer for Jira keys. Automatically adds Jira issue keys to commit messages with backup and rollback support.

## Quick Start

```bash
# Check which commits need Jira keys
./jira-commit.sh audit

# Preview changes
./jira-commit.sh preview PROJ-123

# Add Jira key to commits (creates automatic backup)
./jira-commit.sh amend PROJ-123

# Verify all commits have keys
./jira-commit.sh verify

# Force push
git push --force-with-lease
```

## Commands

| Command | Description |
|---------|-------------|
| `audit` | Show which commits have/need Jira keys |
| `preview <KEY>` | Preview changes without modifying |
| `amend <KEY>` | Add Jira key to commits (with backup) |
| `verify` | Check all commits have Jira keys |
| `rollback [branch]` | Restore from backup |
| `--version` | Show version |
| `--debug` | Enable debug output |

## Commit Format

**Conventional Commits:**
- Before: `feat: Add login`
- After: `feat: PROJ-123 Add login`

**Other formats:**
- Before: `Fix database bug`
- After: `PROJ-123 Fix database bug`

## Safety Features

- Automatic backup: `{branch}_backup_{timestamp}`
- Requires confirmation before rewriting
- Blocks on main/master branches
- Validates clean working directory
- Git-flow compatible

## Example

```bash
# On feature branch
./jira-commit.sh audit
# Shows: 5 commits missing Jira keys

./jira-commit.sh preview AUTH-456
# Shows before/after for each commit

./jira-commit.sh amend AUTH-456
# Creates: feature/my-branch_backup_20250120-143022
# Shows preview, asks confirmation
# Rewrites commit history

./jira-commit.sh verify
# ✓ All 8 commit(s) have Jira keys

git push --force-with-lease
```

## Rollback

```bash
# List backups
./jira-commit.sh rollback

# Restore
./jira-commit.sh rollback feature/my-branch_backup_20250120-143022
```
