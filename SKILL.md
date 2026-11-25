---
name: codex-worker
description: >-
  Orchestrates local OpenAI Codex CLI (`codex exec`) on macOS as a sandboxed coding or audit worker while Antigravity acts as Architect and Code Reviewer.
  Use when the user invokes `/codex-worker` or asks to design a specification and delegate implementation, refactoring, bug fixing, or secondary codebase research to Codex CLI / GPT CLI.
  Do NOT use for trivial one-line edits, pure Q&A, or tasks the user asks Antigravity to execute directly.
---

# Codex Worker Orchestration & Review Skill (macOS)

When this skill is active, operate strictly in an **Architect + Worker + Reviewer** split:

- **Your Role (Antigravity — Gemini / Opus)**: Chief Architect, Spec Writer, and Strict Quality Gatekeeper.
- **Codex CLI's Role (`codex exec`)**: Sandboxed Implementation / Research Worker executing inside the workspace.
- **Hard Boundary**: Do **NOT** directly modify project business source files with `edit_file` or `write_file`. You only author task specification files inside `<workspace>/.codex-tasks/` (and initialize Git if the user asks). All production/test code changes must be performed by Codex CLI and verified by you, unless the user explicitly overrides this boundary or asks you to take over after rework is exhausted.

---

## Pre-Flight Check: Git Repository Baseline

`codex exec` requires a Git repository by default, and `git diff` is essential for your review gate. Before dispatching a task in a workspace:

1. Run `git rev-parse --is-inside-work-tree` in the workspace.
2. **If already a Git repo**:
   - Check `git status --short` and record any pre-existing uncommitted changes before Codex starts so you can separate them during Stage 4 review (or pass `--worktree` if the working tree is dirty and you want isolated changes).
   - Note: `run-codex.zsh` automatically adds `.codex-tasks/` to Git's `info/exclude` (including worktrees and submodules) so task files never pollute `git status` or the project's committed `.gitignore`.
   - Special edge case: if the Git repo was just `git init`-ed with **zero commits** (`git rev-parse --verify HEAD` fails), ask or create an initial baseline commit first so `git diff` works cleanly.
3. **If NOT a Git repo**:
   - Ask the user whether to initialize local Git first (`git init -b main`, `git add .`, `git commit -m "chore: initial baseline"` — **recommended**), or pass `--skip-git-check` if they explicitly prefer running without Git.

---

## Decision Matrix

| Situation | Recommended Dispatch Choice |
| :--- | :--- |
| Clean repo, single implementation or bugfix task | In-place `--work-dir "<workspace>" --sandbox workspace-write` |
| Dirty working tree or parallel write subtasks | Add `--worktree` on initial run (omit on resume) |
| One-off read-only audit with no follow-up expected | `--sandbox read-only --ephemeral` |
| Multi-turn codebase exploration or follow-up expected | `--sandbox read-only` (persists `<summary-file>.session-id`) |
| Multi-file feature or architectural refactor | Briefly confirm Stage 1–2 design before Stage 3 unless end-to-end execution was requested |

---

## 5-Stage Delegation Lifecycle

### Stage 1: DEFINE (Research & Architecture)
1. Inspect the relevant files, types, interfaces, tests, and build scripts yourself.
2. Make all architectural and design decisions upfront (data structures, function/method signatures, file layout, edge cases, and acceptance criteria). Do not leave architectural ambiguity for Codex to guess.
3. If user requirements are ambiguous, clarify with the user **before** writing the spec.

### Stage 2: COMPOSE (Write Task Specification)
1. Pick the matching template from `./resources/`:
   - Feature / refactoring: [implementation-task.md](./resources/implementation-task.md)
   - Bug investigation & fix: [bugfix-task.md](./resources/bugfix-task.md)
   - Read-only exploration / second opinion: [research-task.md](./resources/research-task.md)
2. Write the filled specification to `<workspace>/.codex-tasks/<task-id>-spec.md` (e.g., `.codex-tasks/001-auth-middleware-spec.md`).
3. Always keep the rule in the spec forbidding Codex from running `git commit`, `git push`, `git reset --hard`, or `git checkout --` so every modification remains visible in the working tree for your inspection.

### Stage 3: SPAWN (Dispatch to Local Codex CLI)
Resolve `<skill-dir>` as the directory containing this `SKILL.md` file, then invoke [run-codex.zsh](./scripts/run-codex.zsh) as a black-box CLI (run `zsh "<skill-dir>/scripts/run-codex.zsh" --help` if you need full flag usage):

- **Async & Timeout Rule**: Set `WaitMsBeforeAsync: 10000` and `NotificationTimeoutSeconds: 300` (increase for large refactors) when calling `run_command`. Because `codex` reads `~/.codex` and connects to the OpenAI API, it runs outside Antigravity's terminal sandbox. If backgrounded after 10s, **stop calling tools and wait** — never poll in a loop. If `NotificationTimeoutSeconds` fires while still running, inspect output with `manage_task` (`status`) before deciding to wait or stop.
- **Literal Command Shape**: Resolve `<skill-dir>` and `<workspace-abs-path>` to concrete literal paths. Do **NOT** use `$(...)`, backticks, `<(...)`, `$((...))`, `{a,b}`, or shell variables so Antigravity's `command(...)` permission allow-list prefix-matching works reliably.
- **Parallel Dispatch**: Independent `read-only` audits or isolated `--worktree` write tasks with distinct `<task-id>` spec/summary files may be dispatched as parallel background `run_command` calls in the same turn.

```zsh
# In-place implementation or bugfix:
zsh "<skill-dir>/scripts/run-codex.zsh" --work-dir "<workspace-abs-path>" --spec-file "<workspace-abs-path>/.codex-tasks/<task-id>-spec.md" --summary-file "<workspace-abs-path>/.codex-tasks/<task-id>-summary.md" --sandbox workspace-write

# Isolated worktree implementation (dirty working tree or parallel write tasks):
zsh "<skill-dir>/scripts/run-codex.zsh" --work-dir "<workspace-abs-path>" --spec-file "<workspace-abs-path>/.codex-tasks/<task-id>-spec.md" --summary-file "<workspace-abs-path>/.codex-tasks/<task-id>-summary.md" --sandbox workspace-write --worktree

# One-off read-only research / audit (omit --ephemeral if follow-up is expected):
zsh "<skill-dir>/scripts/run-codex.zsh" --work-dir "<workspace-abs-path>" --spec-file "<workspace-abs-path>/.codex-tasks/<task-id>-spec.md" --summary-file "<workspace-abs-path>/.codex-tasks/<task-id>-summary.md" --sandbox read-only --ephemeral
```

Key flag rules (run `--help` for all options such as `--model`, `--reasoning-effort`, `--add-dir`, `--image`, `--skip-git-check`):
- `run-codex.zsh` defaults to `--model gpt-6.2-astra` and `--reasoning-effort xhigh`; omit both flags unless the user specifies a different model or effort level.
- `--session-id "<id>"` inherits the original task's saved working directory and sandbox; omit `--work-dir`, `--sandbox`, and `--worktree` on resume unless intentionally overriding dir/sandbox.
- `--worktree` requires a new persistent session (cannot combine with `--ephemeral`, `--session-id`, or `--resume-last`).

### Stage 4: REVIEW (Strict Independent Acceptance)
**Never trust Codex's summary at face value.** Perform all three checks yourself:

1. **Read Worker Summary & Checkout Location**: Check the launcher exit code, then read the summary for changes and checks that passed, failed, or could not run. A nonzero exit requires investigation before acceptance. For `--worktree` runs, read `<summary-file>.worktree` (or `[CODEX-WORKER] Worktree : <path>`) to locate the checkout deterministically; only fall back to `git worktree list --porcelain` plus the worker's reported `pwd -P` if multiple worktrees were created concurrently.
2. **Inspect Actual Diffs** (inside the worker's checkout):
   - Run `git status --short` (check for untracked files or unexpected deletions, accounting for any Pre-Flight baseline changes).
   - Run `git diff` (and read new untracked files with `read_file`) to review every changed line against your Stage 2 spec:
     - Did Codex follow the specified architecture, interfaces, and acceptance criteria?
     - Did it touch any forbidden files?
     - Are error handling, types, security, and edge cases properly handled?
3. **Run Independent Verification**: Run the project's test suite, typechecker, or linter yourself in the worker's checkout to confirm everything passes cleanly.

### Stage 5: VERDICT (Approve or Rework)
- **If Review Fails**:
  1. Distinguish reworkable code defects from external/environment blockers (missing credentials, external outage, missing user decision). Escalate external blockers immediately instead of burning rework rounds.
  2. For reworkable defects, write concrete, actionable feedback (exact file paths, line numbers, design deviations, or compiler/test error output) to `<workspace>/.codex-tasks/<task-id>-rework-1.md`.
  3. Read the ID from `<summary-file>.session-id` and dispatch rework with `--session-id "<id>"`, the rework spec, and `<task-id>-rework-1-summary.md` (omitting `--work-dir`, `--sandbox`, and `--worktree`). If `<summary-file>.session-id` is missing, report the failed checks and stop automatic rework.
  4. Repeat Stage 4 review. Limit automatic rework to **at most 2 rounds**; if Codex still fails after 2 rounds, halt and report the exact blocker to the user.
- **If Review Passes**:
  Report concisely to the user:
  1. Architectural design summary;
  2. Files created/modified by Codex;
  3. Your independent review & test verification results;
  4. Handoff status:
     - **In-place mode**: Remind the user that changes are ready in the working tree for their final look or `git commit`.
     - **`--worktree` mode**: State the exact worktree path and branch, and ask whether to `cherry-pick`, `merge`, or apply the changes back to the main working tree.
