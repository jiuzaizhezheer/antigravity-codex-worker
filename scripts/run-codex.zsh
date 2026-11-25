#!/usr/bin/env zsh
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-codex.zsh --spec-file <path> --summary-file <path> [options]

Required:
  --spec-file <path>          Task specification markdown file (piped to stdin)
  --summary-file <path>       Output path for Codex final message (-o)

Options:
  --work-dir <dir>            Workspace directory (new run: current; resume: saved)
  --sandbox <mode>            read-only | workspace-write | danger-full-access
                              (new run: workspace-write; resume: saved)
  --model <slug>              Override Codex model for this run
  --reasoning-effort <level>  minimal | low | medium | high | xhigh | max | ultra
  --session-id <id>           Resume a specific Codex session by ID
  --resume-last               Resume the most recent Codex session in --work-dir
  --skip-git-check            Allow running outside a Git repository
  --image <file>              Attach image file to prompt (repeatable)
  --add-dir <dir>             Grant writable access to extra directory (repeatable)
  --worktree                  Start a persistent new session in a managed Git worktree
  --ephemeral                 Do not persist this run for follow-up
  -h, --help                  Show this help message and exit
EOF
}

require_arg() {
  if [[ $# -lt 2 || -z "$2" ]]; then
    echo "[CODEX-WORKER] Option $1 requires a non-empty argument." >&2
    exit 2
  fi
}

SPEC_FILE=""
SUMMARY_FILE=""
WORK_DIR=""
SANDBOX=""
MODEL=""
REASONING_EFFORT=""
SESSION_ID=""
RESUME_LAST=0
SKIP_GIT_CHECK=0
WORKTREE=0
EPHEMERAL=0
IMAGES=()
ADD_DIRS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec-file)
      require_arg "$@"
      SPEC_FILE="$2"
      shift 2
      ;;
    --summary-file)
      require_arg "$@"
      SUMMARY_FILE="$2"
      shift 2
      ;;
    --work-dir)
      require_arg "$@"
      WORK_DIR="$2"
      shift 2
      ;;
    --sandbox)
      require_arg "$@"
      SANDBOX="$2"
      shift 2
      ;;
    --model)
      require_arg "$@"
      MODEL="$2"
      shift 2
      ;;
    --reasoning-effort)
      require_arg "$@"
      REASONING_EFFORT="$2"
      shift 2
      ;;
    --session-id)
      require_arg "$@"
      SESSION_ID="$2"
      shift 2
      ;;
    --resume-last)
      RESUME_LAST=1
      shift
      ;;
    --skip-git-check)
      SKIP_GIT_CHECK=1
      shift
      ;;
    --image)
      require_arg "$@"
      IMAGES+=("$2")
      shift 2
      ;;
    --add-dir)
      require_arg "$@"
      ADD_DIRS+=("$2")
      shift 2
      ;;
    --worktree)
      WORKTREE=1
      shift
      ;;
    --ephemeral)
      EPHEMERAL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[CODEX-WORKER] Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SPEC_FILE" || -z "$SUMMARY_FILE" ]]; then
  echo "[CODEX-WORKER] --spec-file and --summary-file are required." >&2
  exit 2
fi

case "$SANDBOX" in
  ""|read-only|workspace-write|danger-full-access) ;;
  *)
    echo "[CODEX-WORKER] Invalid --sandbox mode: $SANDBOX (expected: read-only, workspace-write, danger-full-access)" >&2
    exit 2
    ;;
esac

if [[ -n "$REASONING_EFFORT" ]]; then
  case "$REASONING_EFFORT" in
    minimal|low|medium|high|xhigh|max|ultra) ;;
    *)
      echo "[CODEX-WORKER] Invalid --reasoning-effort: $REASONING_EFFORT (expected: minimal, low, medium, high, xhigh, max, ultra)" >&2
      exit 2
      ;;
  esac
fi

if [[ -n "$SESSION_ID" && "$RESUME_LAST" -eq 1 ]]; then
  echo "[CODEX-WORKER] --session-id and --resume-last cannot be used together." >&2
  exit 2
fi

if [[ "$WORKTREE" -eq 1 && ( -n "$SESSION_ID" || "$RESUME_LAST" -eq 1 || "$EPHEMERAL" -eq 1 ) ]]; then
  echo "[CODEX-WORKER] --worktree requires a new, persistent session." >&2
  exit 2
fi
if [[ -z "$SESSION_ID" && "$RESUME_LAST" -eq 0 ]]; then
  WORK_DIR="${WORK_DIR:-$PWD}"
  SANDBOX="${SANDBOX:-workspace-write}"
fi

CODEX_BIN=""
if command -v codex >/dev/null 2>&1; then
  CODEX_BIN="$(command -v codex)"
elif [[ -x "/opt/homebrew/bin/codex" ]]; then
  CODEX_BIN="/opt/homebrew/bin/codex"
elif [[ -x "/usr/local/bin/codex" ]]; then
  CODEX_BIN="/usr/local/bin/codex"
else
  echo "[CODEX-WORKER] Could not locate codex executable in PATH, /opt/homebrew/bin, or /usr/local/bin." >&2
  exit 127
fi

if [[ "$EPHEMERAL" -eq 0 ]] && ! command -v jq >/dev/null 2>&1; then
  echo "[CODEX-WORKER] jq is required to read Codex JSON events." >&2
  exit 127
fi

SPEC_FILE="${SPEC_FILE:A}"
SUMMARY_FILE="${SUMMARY_FILE:A}"
SESSION_FILE="$SUMMARY_FILE.session-id"

if [[ -n "$WORK_DIR" ]]; then
  WORK_DIR="${WORK_DIR:A}"
fi
if [[ -n "$WORK_DIR" && ! -d "$WORK_DIR" ]]; then
  echo "[CODEX-WORKER] Work directory does not exist: $WORK_DIR" >&2
  exit 2
fi
if [[ ! -s "$SPEC_FILE" ]]; then
  echo "[CODEX-WORKER] Spec file missing or empty: $SPEC_FILE" >&2
  exit 2
fi
if [[ "$SPEC_FILE" == "$SUMMARY_FILE" || "$SPEC_FILE" == "$SESSION_FILE" ]]; then
  echo "[CODEX-WORKER] The spec must be separate from the summary and session ID files." >&2
  exit 2
fi

NORMALIZED_IMAGES=()
for img in "${IMAGES[@]}"; do
  img_abs="${img:A}"
  if [[ ! -f "$img_abs" ]]; then
    echo "[CODEX-WORKER] Image file does not exist: $img" >&2
    exit 2
  fi
  NORMALIZED_IMAGES+=("$img_abs")
done
IMAGES=("${NORMALIZED_IMAGES[@]}")

NORMALIZED_ADD_DIRS=()
for dir in "${ADD_DIRS[@]}"; do
  dir_abs="${dir:A}"
  if [[ ! -d "$dir_abs" ]]; then
    echo "[CODEX-WORKER] Additional directory does not exist: $dir" >&2
    exit 2
  fi
  NORMALIZED_ADD_DIRS+=("$dir_abs")
done
ADD_DIRS=("${NORMALIZED_ADD_DIRS[@]}")

mkdir -p "${SUMMARY_FILE:h}"
rm -f "$SUMMARY_FILE" "$SESSION_FILE"

if [[ -n "$WORK_DIR" ]] && EXCLUDE_FILE="$(git -C "$WORK_DIR" rev-parse --git-path info/exclude 2>/dev/null)"; then
  if [[ "$EXCLUDE_FILE" != /* ]]; then
    EXCLUDE_FILE="$WORK_DIR/$EXCLUDE_FILE"
  fi
  mkdir -p "${EXCLUDE_FILE:h}"
  touch "$EXCLUDE_FILE"
  if ! grep -qxF ".codex-tasks/" "$EXCLUDE_FILE"; then
    printf "\n# Antigravity codex-worker task artifacts\n.codex-tasks/\n" >> "$EXCLUDE_FILE"
  fi
fi

ARGS=("exec" "--color" "never")
if [[ -n "$WORK_DIR" ]]; then
  ARGS+=("--cd" "$WORK_DIR")
fi
if [[ -n "$SANDBOX" ]]; then
  ARGS+=("--sandbox" "$SANDBOX")
fi
for dir in "${ADD_DIRS[@]}"; do
  ARGS+=("--add-dir" "$dir")
done

if [[ -n "$SESSION_ID" ]]; then
  ARGS+=("resume")
elif [[ "$RESUME_LAST" -eq 1 ]]; then
  ARGS+=("resume" "--last")
fi

if [[ "$SKIP_GIT_CHECK" -eq 1 ]]; then
  ARGS+=("--skip-git-repo-check")
fi
if [[ "$EPHEMERAL" -eq 1 ]]; then
  ARGS+=("--ephemeral")
fi
if [[ "$WORKTREE" -eq 1 ]]; then
  ARGS+=("--worktree")
fi
if [[ -n "$MODEL" ]]; then
  ARGS+=("--model" "$MODEL")
fi
if [[ -n "$REASONING_EFFORT" ]]; then
  ARGS+=("-c" "model_reasoning_effort=\"$REASONING_EFFORT\"")
fi
for img in "${IMAGES[@]}"; do
  ARGS+=("--image" "$img")
done

if [[ "$EPHEMERAL" -eq 0 ]]; then
  ARGS+=("--json")
fi
ARGS+=("--output-last-message" "$SUMMARY_FILE")
if [[ -n "$SESSION_ID" ]]; then
  ARGS+=("$SESSION_ID")
fi
ARGS+=("-")

RESUME_DESC="none"
if [[ -n "$SESSION_ID" ]]; then
  RESUME_DESC="session:$SESSION_ID"
elif [[ "$RESUME_LAST" -eq 1 ]]; then
  RESUME_DESC="last"
fi

echo "[CODEX-WORKER] Binary  : $CODEX_BIN"
echo "[CODEX-WORKER] WorkDir : ${WORK_DIR:-(saved)}"
echo "[CODEX-WORKER] Sandbox : ${SANDBOX:-(saved)} | Resume: $RESUME_DESC | Model: ${MODEL:-(default)} | Effort: ${REASONING_EFFORT:-(default)} | Ephemeral: $EPHEMERAL | Worktree: $WORKTREE"
echo "[CODEX-WORKER] Spec    : $SPEC_FILE"
echo "[CODEX-WORKER] Summary : $SUMMARY_FILE"
echo "------------------------------------------------------------"

exit_code=0
if [[ "$EPHEMERAL" -eq 0 ]]; then
  RUN_LOG="$(mktemp "${TMPDIR:-/tmp}/codex-worker.XXXXXX")"
  trap 'rm -f "$RUN_LOG"' EXIT

  (
    cd "${WORK_DIR:-$PWD}" || exit 1
    "$CODEX_BIN" "${ARGS[@]}" < "$SPEC_FILE"
  ) > "$RUN_LOG" || exit_code=$?

  echo "------------------------------------------------------------"
  if DETECTED_SESSION_ID="$(jq -ner 'first(inputs | select(.type == "thread.started") | .thread_id | strings | select(length > 0))' "$RUN_LOG" 2>/dev/null)"; then
    print -r -- "$DETECTED_SESSION_ID" > "$SESSION_FILE"
    echo "[CODEX-WORKER] Session : $DETECTED_SESSION_ID"
  else
    echo "[CODEX-WORKER] No session ID received. Automatic rework is unavailable." >&2
  fi

  if [[ "$exit_code" -ne 0 && -s "$RUN_LOG" ]]; then
    ERROR_LINES="$(jq -Rr 'fromjson? | select(.type == "error" or .type == "turn.failed") | .message // .error.message // empty' "$RUN_LOG" 2>/dev/null || true)"
    if [[ -n "$ERROR_LINES" ]]; then
      print -r -- "$ERROR_LINES" >&2
    else
      tail -n 20 "$RUN_LOG" >&2
    fi
  fi
else
  (
    cd "${WORK_DIR:-$PWD}" || exit 1
    "$CODEX_BIN" "${ARGS[@]}" < "$SPEC_FILE"
  ) || exit_code=$?
  echo "------------------------------------------------------------"
fi

if [[ "$exit_code" -ne 0 ]]; then
  echo "[CODEX-WORKER] Run failed with exit code: $exit_code" >&2
  exit "$exit_code"
fi
if [[ ! -f "$SUMMARY_FILE" ]] || ! grep -q '[^[:space:]]' "$SUMMARY_FILE"; then
  echo "[CODEX-WORKER] Missing or empty final summary: $SUMMARY_FILE" >&2
  exit 1
fi
echo "[CODEX-WORKER] Completed successfully. Final summary saved to: $SUMMARY_FILE"
