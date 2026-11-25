# antigravity-codex-worker

**Use Gemini / Claude Opus in Google Antigravity as your Chief Architect & Code Reviewer, while delegating sandboxed implementation to your local OpenAI Codex CLI (`codex exec`) — zero MCP bridges or third-party middleware required.**

**无需任何第三方桥接插件或 MCP Server：在 Google Antigravity 中用 Gemini / Claude Opus 担任架构师与代码审查员，通过标准化任务契约指挥本地 OpenAI Codex CLI 在沙盒中写代码并完成闭环验收。**

---

## English Guide

### Why This Skill?
Different frontier models excel at different stages of software engineering. `antigravity-codex-worker` establishes a clean **Architect + Worker + Reviewer** separation inside Antigravity using only native Agent Skills and `codex exec` headless mode:

1. **DEFINE** — Antigravity explores the codebase and resolves architectural decisions upfront.
2. **COMPOSE** — Antigravity writes a structured specification file (`.codex-tasks/<id>-spec.md`) using strict scope templates.
3. **SPAWN** — `run-codex.ps1` (Windows) or `run-codex.sh` (macOS/Linux) pipes the spec via UTF-8 `stdin` into `codex exec --sandbox workspace-write` (avoiding shell-quoting truncation or encoding issues) and captures Codex's report via `--output-last-message`.
4. **REVIEW** — Antigravity independently inspects `git status`, line-by-line `git diff`, and runs local test/build suites in its own sandbox rather than trusting the worker's summary blindly.
5. **VERDICT** — Approves changes or triggers up to 2 targeted rework rounds via `codex exec resume --last`.

```text
Antigravity (Gemini / Opus)           Workspace (.codex-tasks/)           OpenAI Codex CLI
───────────────────────────           ─────────────────────────           ────────────────
1. Architecture & Spec Design  ────>  001-feature-spec.md
2. Invoke run-codex.ps1/.sh    ────   UTF-8 stdin pipe   ──────────────>  codex exec (workspace-write)
                                                                            ├─ Edits files in workspace
                                      001-feature-summary.md <── (-o) ──    └─ Writes structured summary
3. Independent Review Gate:
   ├─ Read summary + inspect `git diff`
   ├─ Run tests / typecheck / linter
   └─ Pass -> Report to user | Fail -> `codex exec resume --last` rework
```

### Key Features
- **Zero Middleware**: Pure `SKILL.md` + native PowerShell / Bash wrappers over official `codex exec`.
- **Per-Task Model & Thinking Effort Control**: Dynamically override `--model` (`-Model`) and `model_reasoning_effort` (`-ReasoningEffort`: `minimal` | `low` | `medium` | `high` | `xhigh` | `max` | `ultra`) per task without mutating `~/.codex/config.toml`.
- **Clean Git Hygiene**: Automatically registers `.codex-tasks/` in local `.git/info/exclude` so task specs never pollute `git status` or modify your tracked `.gitignore`.
- **Session-Preserving Rework**: Failed acceptance gates resume the exact Codex session (`resume --last`) with file/line review feedback.

### Prerequisites
- [Google Antigravity](https://antigravity.google/) IDE / CLI
- [OpenAI Codex](https://github.com/openai/codex) CLI installed and signed in (`codex login` or via the OpenAI Codex desktop app)
- `git` initialized in your target project (with at least one baseline commit for `git diff` review)

### Installation

#### Option A: Global Install (Recommended — available in all projects)
```powershell
# Windows (PowerShell)
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git "$HOME\.gemini\config\skills\codex-worker"
```
```bash
# macOS / Linux
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git ~/.gemini/config/skills/codex-worker
chmod +x ~/.gemini/config/skills/codex-worker/scripts/run-codex.sh
```

#### Option B: Workspace-Only Install
```bash
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git .agents/skills/codex-worker
```

### Usage Examples
Start a new conversation in Antigravity and prompt naturally:
- *"Use `codex-worker`: design the pagination refactor for `src/api/users.ts`, confirm the plan with me, delegate coding to Codex, and review the diff + unit tests."*
- *"Use `codex-worker` to fix this bug; dispatch to Codex with `low` reasoning effort since the fix is straightforward."*
- *"Design the concurrency scheduler and dispatch to Codex with `xhigh` reasoning effort."*

---

## 中文说明

### 核心设计思路
利用 Antigravity 原生 Skill 机制，将 **顶层架构设计/验收（Gemini / Claude Opus）** 与 **底层代码施工（OpenAI Codex CLI）** 解耦：

1. **文件契约交接（防转义与乱码）**：主模型将架构设计、允许修改的文件边界、禁止事项（严禁自动 `git commit`）写入 `.codex-tasks/<id>-spec.md`，脚本通过 UTF-8 无 BOM 标准输入流喂给 `codex exec`，彻底规避 Windows/Shell 长文本参数截断与中文乱码问题。
2. **双层安全边界**：Codex 自身运行在 `--sandbox workspace-write`（或只读调研 `read-only`）沙盒中；任务单自动写入本地 `.git/info/exclude`，不污染 `git status`，也不改动项目原本的 `.gitignore`。
3. **客观验收关卡（Review Gate）**：主模型绝不轻信 Codex 的口头总结，而是亲自检查 `git diff` 并运行单测/类型检查；若不达标，自动通过 `-ResumeLast` 续接同一会话打回返工（最多 2 轮）。
4. **按需指定模型与思考强度**：每次派发可单独指定 `-Model` 与 `-ReasoningEffort`（`low` / `medium` / `high` / `xhigh` / `max` / `ultra`），不影响 `~/.codex/config.toml` 默认配置。

### 快速安装（全局生效）
```powershell
# Windows PowerShell
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git "$HOME\.gemini\config\skills\codex-worker"
```
```bash
# macOS / Linux
git clone https://github.com/jiuzaizhezheer/antigravity-codex-worker.git ~/.gemini/config/skills/codex-worker
chmod +x ~/.gemini/config/skills/codex-worker/scripts/run-codex.sh
```

### 日常对话示例
新开一个 Antigravity 对话即可触发：
- *“用 `codex-worker` 模式：先帮我设计鉴权中间件的方案，确认后交给 Codex 实现，改完你来审 `git diff` 并跑测试验收。”*
- *“这个小改动方案写细一点，让 Codex 用 `low` 思考强度去改就行，省点额度。”*
- *“这块并发逻辑比较复杂，派发给 Codex 时把思考强度开到 `xhigh`。”*

---

## Repository Structure
```text
codex-worker/
├── SKILL.md                        # Orchestration & 5-stage review protocol
├── scripts/
│   ├── run-codex.ps1               # Windows PowerShell headless launcher
│   └── run-codex.sh                # macOS / Linux Bash headless launcher
├── resources/
│   ├── implementation-task.md      # Feature & refactoring spec template
│   ├── bugfix-task.md              # Root-cause & surgical bugfix template
│   └── research-task.md            # Read-only audit & exploration template
└── LICENSE                         # MIT License
```

## Credits
- Maintained as an independent derivative by [jiuzaizhezheer](https://github.com/jiuzaizhezheer).
- Derived from [lbc9168/antigravity-codex-worker](https://github.com/lbc9168/antigravity-codex-worker) by Bingcai Liu (MIT License).
- Delegation lifecycle originally inspired by [khanhbkqt/spawn-agent](https://github.com/khanhbkqt/spawn-agent).
