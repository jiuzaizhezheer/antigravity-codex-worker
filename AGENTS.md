# Repository Guidelines (`antigravity-codex-worker`)

These rules apply when modifying or iterating on `antigravity-codex-worker` itself.

## Commit Attribution (Required)
- Every commit made during iterations on this repository itself must include an attribution trailer identifying the agent and model in the format `AgentName-ModelName` (using human-readable names):
  - `Co-authored-by: AgentName-ModelName <noreply@example.com>`
  - Example: `Co-authored-by: Antigravity-Gemini 4 Neon <noreply@antigravity.google>`
  - Example: `Co-authored-by: Codex-GPT 6.2 Astra <noreply@openai.com>`

## Repository Conventions
- **Language**: Write all repository files, documentation, comments, and templates in concise, precise English.
- **Target Platform**: Target macOS exclusively with native `zsh` execution via [scripts/run-codex.zsh](./scripts/run-codex.zsh); do not add support or workarounds for other platforms.
- **License Hygiene**: Preserve existing MIT copyright notices in [LICENSE](./LICENSE).
