## 1. Project Overview

This repository, `shell-zoo`, is a collection of bash scripts for various command-line tasks and automation.

**Technologies used:**

- Bash scripting

## 2. Coding Standards

- **Indentation:**
  - Bash scripts use 4 spaces.
- **Naming Conventions:**
  - Bash:
    - Scripts: Use descriptive, lower-kebab-case for Bash scripts (e.g., `image-to-data-url.sh`, `test-setup.sh`).
    - Variables: Use lower_snake_case for Bash variables (e.g., `s3_bucket_eci_name`, `expiration_days_for_eci_objects`).
    - Constants: Use UPPER_SNAKE_CASE for constants (e.g., `readonly GREEN`, `readonly YELLOW`).
    - Exports: Use UPPER_SNAKE_CASE for exported variables (e.g., `export S3_BUCKET_ECI_NAME`) that are meant to be used in other scripts or processes. Internally, use lower_snake_case.
    - Functions: Use lower_snake_case for Bash functions (e.g., `function_name`).
    - Maintainability: Write clean, modular code with functions and clear variable names. Do not repeat yourself (DRY principle). The `main` part of the script should be clearly defined and separated from function definitions, and it should be written in a way that anyone can easily understand what the script does. The main part should mostly be focused on orchestrating the workflow and calling the appropriate functions.
    - Cross-Platform Compatibility: Scripts should be compatible with both macOS and Linux environments.
- **Commenting/Documentation:**
  - Use `#` for comments in Bash. Explain non-obvious logic.
- **Formatting:**
  - Bash scripts should be shellcheck clean and formatting should be consistent using `shfmt`.
- **Linters/Formatters:**
  - Use `shellcheck` and `shfmt` for Bash scripts to ensure they are clean and consistently formatted.
- **Dependencies**:
  - Scripts should preferably use tools that are ubiquitously available in standard shell environments.
  - If a less common utility is required, it should be a well-known and widely used tool (e.g., `jq`, `fzf`).
  - Validate that any new dependencies are installed and available in the script, and provide clear error messages if they are not.
- **Bash Version**:
  - The minimum required Bash version for scripts in this repository is 5.1.

## 3. Directory and File Structure

- **Root directory**: Contains scripts and supporting files.

  - `README.md`: Project overview, usage, and documentation.

- **`docs/`**: Documentation for the project.

  - Add new documentation here for design, architecture, or operational runbooks.

### Where to put new files

- **New scripts**: Place operational or helper scripts in the project root.
- **New documentation**: Add markdown files to the `docs/` directory.

## 4. Testing and Validation

- Ensure all scripts pass `shellcheck` and are formatted with `shfmt`.
- Update or add tests and documentation as needed for new features or changes.

## 5. Security and Compliance

- Never expose or store secrets.
- Review and document any security exceptions or trade-offs in code comments.

## 6. When Making Changes
 - Always focus on just the task described in the prompt.
 - Always be conservative in making changes.
 - Avoid making changes that are not directly related to the task.
 - Avoid modifying comments in unrelated parts of the code.
 - Avoid renaming existing variables where possible.
 - Avoid adding comments that explain a change, instead explain what the code is doing and why.
 - Avoid very long paragraphs of comments where possible. Be precise and brief.
 - Before making changes to a file, always read the entire file and any related contents or section to ensure complete context.
 - If a patch is not applied correctly, attempt to reapply it once again. Do not try to apply the patch more than twice. Give up and describe the changes you were trying to make.
 - Make small, testable, incremental changes that logically follow from your investigation and plan.
