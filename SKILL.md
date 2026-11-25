---
name: codex-worker
description: >-
  Orchestrate local OpenAI Codex CLI (`codex exec`) on macOS as a sandboxed coding worker while you act as Architect and Code Reviewer.
  Activate this skill whenever the user asks to design a plan/spec and delegate coding, refactoring, bug fixing, or secondary codebase research to Codex CLI / GPT CLI (e.g., "delegate implementation to Codex", "design a spec and hand off coding to Codex CLI", "use architect + Codex worker mode", "run a read-only audit with Codex").
---

# Codex Worker Orchestration & Review Skill (macOS)

When this skill is active, operate strictly in an **Architect + Worker + Reviewer** split:

- **Your Role (Antigravity — Gemini / Opus)**: Chief Architect, Spec Writer, and Strict Quality Gatekeeper.
- **Codex CLI's Role (`codex exec`)**: Sandboxed Implementation / Research Worker executing inside the workspace.
- **Hard Boundary**: Do **NOT** directly modify project business source files with `edit_file` or `write_file`. You only author task specification files inside `<workspace>/.codex-tasks/` (and initialize Git if the user asks). All production/test code changes must be performed by Codex CLI and verified by you.

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
Resolve `<skill-dir>` as the directory containing this `SKILL.md` file, then invoke [run-codex.zsh](./scripts/run-codex.zsh):

- **Execution Rule**: Set `WaitMsBeforeAsync: 10000` when calling `run_command`.
- **Async Handling**: Coding tasks often take 30–180 seconds. If the command moves to background after 10 seconds, **stop calling tools and wait** — the system automatically wakes you when the background task finishes. Never poll in a loop.
- **Command Shape** (resolve `<skill-dir>` and `<workspace-abs-path>` to concrete literal paths — avoid `$(...)` or shell variables so user approval prefix-matches cleanly):

```zsh
# Implementation or Bugfix:
zsh "<skill-dir>/scripts/run-codex.zsh" --work-dir "<workspace-abs-path>" --spec-file "<workspace-abs-path>/.codex-tasks/<task-id>-spec.md" --summary-file "<workspace-abs-path>/.codex-tasks/<task-id>-summary.md" --sandbox workspace-write

# Read-only research with the option to follow up:
zsh "<skill-dir>/scripts/run-codex.zsh" --work-dir "<workspace-abs-path>" --spec-file "<workspace-abs-path>/.codex-tasks/<task-id>-spec.md" --summary-file "<workspace-abs-path>/.codex-tasks/<task-id>-summary.md" --sandbox read-only
```

Optional flags supported by `run-codex.zsh`:
- `--model "<model-slug>"`: Overrides Codex's default model for this run. Only set when the user asks for a specific model; omit otherwise to use `~/.codex/config.toml` default.
- `--reasoning-effort "<level>"`: Overrides Codex's thinking effort (`minimal`, `low`, `medium`, `high`, `xhigh`, `max`, `ultra`) via `-c model_reasoning_effort=...`. Set when the user requests a specific thinking intensity; omit otherwise to use `~/.codex/config.toml` default.
- `--session-id "<id>"`: Resumes that task's saved directory, workspace roots, and sandbox. Pass `--work-dir` or `--sandbox` on resume only for an intentional override.
- `--resume-last`: Selects the most recent session for the current or specified directory. Use only when explicitly requested.
- `--add-dir "<dir>"`: Grants writable access to an additional directory alongside `--work-dir` (repeatable).
- `--worktree`: Starts a new persistent session in a managed Git worktree. Omit it on resume.
- `--ephemeral`: Opts into a one-off run when follow-up is unnecessary. It is incompatible with `--worktree`.
- `--skip-git-check`: Allows execution outside a Git repository when explicitly requested.
- `--image "<file-path>"`: Attaches reference screenshot/mockup file(s) to the prompt (repeatable).

### Stage 4: REVIEW (Strict Independent Acceptance)
**Never trust Codex's summary at face value.** Perform all three checks yourself:

1. **Read Worker Summary**: Check the launcher exit code, then read the summary for the working directory, changes, and checks that passed, failed, or could not run. A nonzero exit requires investigation before acceptance.
2. **Inspect Actual Diffs**:
   - Run all review commands and tests in the worker's checkout. For `--worktree`, match the directory reported by the worker to an entry in `git worktree list --porcelain` before reviewing the diff.
   - Run `git status --short` (check for untracked files or unexpected deletions, accounting for any Pre-Flight baseline changes).
   - Run `git diff` (and read new untracked files with `read_file`) to review every changed line against your Stage 2 spec:
     - Did Codex follow the specified architecture, interfaces, and acceptance criteria?
     - Did it touch any forbidden files?
     - Are error handling, types, security, and edge cases properly handled?
3. **Run Independent Verification**: Run the project's test suite, typechecker, or linter yourself to confirm everything passes cleanly.

### Stage 5: VERDICT (Approve or Rework)
- **If Review Fails**:
  1. Write concrete, actionable feedback (exact file paths, line numbers, design deviations, or compiler/test error output) to `<workspace>/.codex-tasks/<task-id>-rework-1.md`.
  2. Read the ID from the original task's `<summary-file>.session-id` and pass it to `--session-id`. Supply the rework spec and a new summary path. Omit `--work-dir`, `--sandbox`, and `--worktree` to reuse the original environment. If the ID is unavailable, report the failed checks and stop automatic rework.
  3. Repeat Stage 4 review. Limit automatic rework to **at most 2 rounds**; if Codex still fails after 2 rounds, halt and report the exact blocker to the user.
- **If Review Passes**:
  Report concisely to the user:
  1. Architectural design summary;
  2. Files created/modified by Codex;
  3. Your independent review & test verification results;
  4. Remind the user that changes are ready in the working tree for their final look or `git commit`.
