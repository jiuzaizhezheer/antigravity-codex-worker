# antigravity-codex-worker (macOS)

**Use Gemini or Claude Opus in Google Antigravity on macOS as your Chief Architect and Code Reviewer, while delegating sandboxed execution to your local OpenAI Codex CLI (`codex exec`) — zero MCP servers or bridge middleware required.**

---

## Workflow Overview

`antigravity-codex-worker` enforces a strict **Architect + Worker + Reviewer** separation using native Antigravity Agent Skills and `codex exec` headless mode:

1. **DEFINE** — Antigravity inspects the codebase and resolves architectural decisions, interfaces, and edge cases upfront.
2. **COMPOSE** — Antigravity writes a structured specification file (`.codex-tasks/<task-id>-spec.md`) from scoped task templates.
3. **SPAWN** — [scripts/run-codex.zsh](./scripts/run-codex.zsh) pipes the specification via `stdin` into `codex exec --sandbox <mode>` and captures the final report via `--output-last-message`.
4. **REVIEW** — Antigravity independently inspects `git status --short`, line-by-line `git diff`, and runs tests/linters/typecheckers itself rather than trusting the worker's summary.
5. **VERDICT** — Approves changes in the working tree or dispatches up to 2 targeted rework rounds using `--session-id` (or `--resume-last` fallback).

```text
Antigravity (Gemini / Opus)           Workspace (.codex-tasks/)           OpenAI Codex CLI
───────────────────────────           ─────────────────────────           ────────────────
1. Architecture & Spec Design  ────>  001-feature-spec.md
2. Invoke run-codex.zsh        ────   stdin pipe        ──────────────>  codex exec (workspace-write)
                                                                            ├─ Edits files in workspace
                                      001-feature-summary.md <── (-o) ──    └─ Writes structured summary
3. Independent Review Gate:
   ├─ Read summary + inspect `git diff`
   ├─ Run tests / typecheck / linter
   └─ Pass -> Report to user | Fail -> `--session-id` rework (max 2 rounds)
```

### Key Features
- **macOS-Native `zsh` Launcher**: Pure `SKILL.md` + `zsh` wrapper over official `codex exec` with zero external runtime dependencies. Resolves `codex` from `PATH`, `/opt/homebrew/bin/codex`, or `/usr/local/bin/codex`, and normalizes all paths to absolute paths before changing directories.
- **File-Contract `stdin` Handoff**: Specs in `.codex-tasks/<task-id>-spec.md` are streamed via `stdin` to avoid shell quoting and argument-length issues. Templates forbid `git commit`, `git push`, `git reset --hard`, and `git checkout --`, keeping all edits unstaged for review.
- **Session-ID-Targeted Rework**: Captures `session id` from Codex execution output and prints `[CODEX-WORKER] Session : <id>` so rework rounds resume the exact session via `--session-id` without cross-session collisions (with `--resume-last` retained as fallback).
- **Worktree-Safe Git Hygiene**: Uses `git rev-parse --git-path info/exclude` to register `.codex-tasks/` cleanly across standard repositories, subdirectories, submodules, and `git worktree` checkouts without modifying tracked `.gitignore` files.
- **Per-Task Execution Controls**: Supports per-invocation overrides for `--model`, `--reasoning-effort`, `--add-dir`, and `--worktree` without mutating `~/.codex/config.toml`. Non-resumed `--sandbox read-only` runs automatically enable `--ephemeral` to avoid cluttering saved session history.

---

## Prerequisites
- macOS with `zsh`
- [Google Antigravity](https://antigravity.google/)
- [OpenAI Codex](https://github.com/openai/codex) CLI installed and authenticated (`codex login` or via the Codex desktop app)
- Target workspace initialized with `git` (and at least one baseline commit for `git diff` review, unless `--skip-git-check` is used)

---

## Installation

### Global Install (Recommended — available across all workspaces)
```zsh
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git ~/.agents/skills/codex-worker
chmod +x ~/.agents/skills/codex-worker/scripts/run-codex.zsh
```
> Alternatively, install to `~/.gemini/config/skills/codex-worker`.

### Workspace-Only Install
```zsh
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git .agents/skills/codex-worker
chmod +x .agents/skills/codex-worker/scripts/run-codex.zsh
```

---

## Usage Examples
Start a conversation in Antigravity and prompt naturally:
- *"Use `codex-worker`: design the pagination refactor for `src/api/users.ts`, confirm the plan with me, delegate coding to Codex, and review the diff + unit tests."*
- *"Use `codex-worker` to fix this bug; dispatch to Codex with `low` reasoning effort since the fix is straightforward."*
- *"Design the concurrency scheduler and dispatch to Codex with `xhigh` reasoning effort."*

---

## `run-codex.zsh` Options

| Option | Description |
| :--- | :--- |
| `--spec-file <path>` | **Required.** Task specification markdown file piped to `codex` via `stdin`. |
| `--summary-file <path>` | **Required.** Output file path passed to `--output-last-message` (`-o`). |
| `--work-dir <dir>` | Target workspace root (defaults to current working directory). |
| `--sandbox <mode>` | Sandbox policy: `read-only`, `workspace-write` (default), or `danger-full-access`. |
| `--model <slug>` | Override the Codex model for this invocation. |
| `--reasoning-effort <level>` | Override `model_reasoning_effort`: `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, or `ultra`. |
| `--session-id <id>` | Resume a specific Codex session by ID (mutually exclusive with `--resume-last`). |
| `--resume-last` | Resume the most recent Codex session recorded for `--work-dir`. |
| `--add-dir <dir>` | Grant writable access to an additional directory alongside `--work-dir` (repeatable). |
| `--worktree` | Execute inside a new managed Git worktree. |
| `--ephemeral` | Do not persist session files to disk (auto-enabled for non-resumed `--sandbox read-only`). |
| `--skip-git-check` | Allow execution outside a Git repository. |
| `--image <file>` | Attach an image file to the prompt (repeatable). |
| `-h`, `--help` | Print CLI usage and exit. |

---

## Repository Structure
```text
antigravity-codex-worker/
├── SKILL.md                        # Orchestration rules & 5-stage review protocol
├── scripts/
│   └── run-codex.zsh               # macOS zsh headless launcher
├── resources/
│   ├── implementation-task.md      # Feature & refactoring specification template
│   ├── bugfix-task.md              # Root-cause investigation & bugfix template
│   └── research-task.md            # Read-only audit & exploration template
└── LICENSE                         # MIT License
```

## Credits
- Maintained as a macOS-focused derivative by [jiuzaizhezheer](https://github.com/jiuzaizhezheer).
- Derived from [lbc9168/antigravity-codex-worker](https://github.com/lbc9168/antigravity-codex-worker) by Bingcai Liu (MIT License).
- Delegation lifecycle originally inspired by [khanhbkqt/spawn-agent](https://github.com/khanhbkqt/spawn-agent).
