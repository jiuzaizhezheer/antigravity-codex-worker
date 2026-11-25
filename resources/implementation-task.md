# Implementation Task Specification: {{TASK_ID}}

## 1. Objective
<!-- State clearly in 1-3 sentences what feature or refactoring is being built and why. -->

## 2. Scope & File Boundaries
- **Files to Create / Modify**:
  - `path/to/target_file` — purpose of changes
- **Read-Only Reference Files** (inspect for types/conventions, do NOT modify):
  - `path/to/reference_file`
- **Strict Constraints (Forbidden Actions)**:
  - Do NOT modify files outside the allowed scope above unless strictly required for compilation (if so, document why in your summary).
  - Do NOT run `git commit`, `git push`, `git reset --hard`, or `git checkout --`. Leave all edits unstaged in the working tree for architectural review.
  - Do NOT touch `.codex-tasks/`.

## 3. Entry Point & Acceptance Criteria
- **Entry point**: Where the user or caller exercises this behavior.
- **Expected result**: A concrete input or scenario and its observable outcome.
- **Compatibility**: Existing interfaces and behavior that must be preserved.

## 4. Self-Verification Requirements
Run the following command(s) inside the workspace before finishing and fix any errors introduced by your changes:
```text
{{VERIFY_COMMANDS}}
```

## 5. Required Final Summary Format
In your final response message, provide a structured report with:
1. **Changed Files**: List of every created/modified file and a 1-line summary of each change.
2. **Verification**: Report the working directory (`pwd -P`), commands run, results, and any checks skipped or blocked with reasons.
3. **Deviations / Risks**: Any assumptions made or edge cases requiring the architect's attention.
