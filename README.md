# antigravity-codex-worker (macOS)

**Use Gemini or Claude Opus in Google Antigravity on macOS as your Chief Architect and Code Reviewer, while delegating sandboxed execution to your local OpenAI Codex CLI (`codex exec`) — zero MCP servers or bridge middleware required.**

---

## Workflow Overview

`antigravity-codex-worker` enforces a strict **Architect + Worker + Reviewer** separation using native Antigravity Agent Skills and `codex exec` headless mode:

1. **DEFINE** — Antigravity inspects the codebase and resolves architectural decisions, interfaces, edge cases, and acceptance criteria upfront.
2. **COMPOSE** — Antigravity writes a structured specification file (`.codex-tasks/<task-id>-spec.md`) from scoped task templates.
3. **SPAWN** — [scripts/run-codex.zsh](./scripts/run-codex.zsh) pipes the specification via `stdin` into `codex exec --sandbox <mode>` and captures the final report via `--output-last-message`.
4. **REVIEW** — Antigravity inspects the diff and runs the acceptance checks in the worker's actual checkout. The launcher reports failure if Codex exits unsuccessfully or the final summary is missing or empty.
5. **VERDICT** — Approves changes in the working tree (or reports the `--worktree` checkout for integration) or dispatches up to 2 targeted rework rounds using the task's saved session ID.

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
- **macOS-Native `zsh` Launcher**: Resolves `codex` from `PATH`, `/opt/homebrew/bin/codex`, or `/usr/local/bin/codex`, and normalizes file paths before changing directories.
- **File-Contract `stdin` Handoff**: Specs in `.codex-tasks/<task-id>-spec.md` are streamed via `stdin` to avoid shell quoting and argument-length issues. Templates forbid `git commit`, `git push`, `git reset --hard`, and `git checkout --`, keeping all edits unstaged for review.
- **Session-ID-Targeted Rework**: Reads `thread_id` from the `thread.started` JSONL event (captured internally without flooding stdout) and saves it in `<summary-file>.session-id` for persistent runs. Automatic rework uses this ID and inherits the saved workspace and sandbox. A missing ID disables automatic rework.
- **Deterministic `--worktree` Tracking & Parallel Dispatch**: Snapshots `git worktree list --porcelain` before and after `--worktree` runs, recording the new checkout path in `<summary-file>.worktree` (`[CODEX-WORKER] Worktree : <path>`). Independent `read-only` or `--worktree` tasks can run in parallel.
- **Worktree-Safe Git Hygiene**: Uses `git rev-parse --git-path info/exclude` to register `.codex-tasks/` cleanly across standard repositories, subdirectories, submodules, and `git worktree` checkouts without modifying tracked `.gitignore` files.
- **Per-Task Execution Controls**: Supports per-invocation overrides for `--model`, `--reasoning-effort`, `--add-dir`, and `--worktree` without mutating `~/.codex/config.toml`. Use `--ephemeral` for one-off tasks (skips `--json` and `jq`).

---

## Prerequisites
- macOS with `zsh` and `jq`
- [Google Antigravity](https://antigravity.google/) (App, IDE, or `agy` CLI)
- [OpenAI Codex](https://github.com/openai/codex) CLI installed and authenticated (`codex login` or via the Codex desktop app)
- Target workspace initialized with `git` (and at least one baseline commit for `git diff` review, unless `--skip-git-check` is used)

---

## Installation

### Global Install — Antigravity App / IDE (Recommended)
```zsh
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git ~/.gemini/config/skills/codex-worker
chmod +x ~/.gemini/config/skills/codex-worker/scripts/run-codex.zsh
```

### Global Install — Antigravity CLI (`agy`) or Shared Cross-Agent Path
```zsh
# Antigravity CLI global skills:
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git ~/.gemini/antigravity-cli/skills/codex-worker
chmod +x ~/.gemini/antigravity-cli/skills/codex-worker/scripts/run-codex.zsh

# Or shared ~/.agents/skills path:
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git ~/.agents/skills/codex-worker
chmod +x ~/.agents/skills/codex-worker/scripts/run-codex.zsh
```

### Workspace-Only Install
```zsh
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git .agents/skills/codex-worker
chmod +x .agents/skills/codex-worker/scripts/run-codex.zsh
```

---

## Antigravity Permissions & Sandbox Setup

Antigravity's macOS terminal sandbox (`sandbox-exec`) blocks outbound network access and hides `~/.codex` by default, so `run-codex.zsh` runs outside Antigravity's sandbox (while Codex still enforces its own `--sandbox` policy).

Under Antigravity's **Default** permission preset, each invocation prompts for approval unless allow-listed. To allow this launcher without weakening your global sandbox preset, add a single literal `command(...)` Allow rule matching your install path:

```text
command(zsh /Users/<you>/.gemini/config/skills/codex-worker/scripts/run-codex.zsh)
```

---

## Usage Examples
In Antigravity App or CLI, invoke explicitly with `/codex-worker` or prompt naturally:
- *"/codex-worker design the pagination refactor for `src/api/users.ts`, confirm the plan with me, delegate coding to Codex, and review the diff + unit tests."*
- *"Use `codex-worker` to fix this bug; dispatch to Codex with `low` reasoning effort since the fix is straightforward."*
- *"Design the concurrency scheduler and dispatch to Codex in a `--worktree` with `xhigh` reasoning effort."*

---

## `run-codex.zsh` Options

| Option | Description |
| :--- | :--- |
| `--spec-file <path>` | **Required.** Task specification markdown file piped to `codex` via `stdin`. |
| `--summary-file <path>` | **Required.** Output file path passed to `--output-last-message` (`-o`). |
| `--work-dir <dir>` | Defaults to the current directory for new runs and the saved directory on resume. |
| `--sandbox <mode>` | `read-only`, `workspace-write`, or `danger-full-access`. Defaults to `workspace-write` for new runs and the saved policy on resume. |
| `--model <slug>` | Codex model for this invocation (default: `gpt-6.2-astra`). |
| `--reasoning-effort <level>` | `model_reasoning_effort`: `minimal`, `low`, `medium`, `high`, `xhigh` (default), `max`, or `ultra`. |
| `--session-id <id>` | Resume a specific Codex session by ID (mutually exclusive with `--resume-last`). |
| `--resume-last` | Resume the most recent Codex session recorded for `--work-dir`. |
| `--add-dir <dir>` | Grant writable access to an additional directory alongside `--work-dir` (repeatable). |
| `--worktree` | Start a new persistent session in a managed Git worktree. Incompatible with resume and `--ephemeral`. |
| `--ephemeral` | Skip session persistence for this run (omits `--json` and `jq`). Available for both read-only and writable tasks. |
| `--skip-git-check` | Allow execution outside a Git repository. |
| `--image <file>` | Attach an image file to the prompt (repeatable). |
| `-h`, `--help` | Print CLI usage and exit. |

---

## Repository Structure
```text
antigravity-codex-worker/
├── AGENTS.md                       # Repository-level rules for self-iteration
├── SKILL.md                        # Orchestration rules & 5-stage review protocol
├── scripts/
│   └── run-codex.zsh               # macOS zsh headless launcher
├── resources/
│   ├── implementation-task.md      # Feature & refactoring specification template
│   ├── bugfix-task.md              # Root-cause investigation & bugfix template
│   └── research-task.md            # Read-only audit & exploration template
├── tests/
│   └── run-codex.zsh               # Launcher regression test suite
└── LICENSE                         # MIT License
```

## Credits
- Maintained as a macOS-focused derivative by [jiuzaizhezheer](https://github.com/jiuzaizhezheer).
- Derived from [lbc9168/antigravity-codex-worker](https://github.com/lbc9168/antigravity-codex-worker) by Bingcai Liu (MIT License).
- Delegation lifecycle originally inspired by [khanhbkqt/spawn-agent](https://github.com/khanhbkqt/spawn-agent).
