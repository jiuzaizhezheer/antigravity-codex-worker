#!/usr/bin/env zsh
set -euo pipefail

launcher=${0:A:h:h}/scripts/run-codex.zsh
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cd "$test_dir"
mkdir bin
git init -q 'worker checkout'
export PATH="$PWD/bin:$PATH" ARGS_FILE="$PWD/args"
print -r -- 'Task with spaces' > spec.md

cat > bin/codex <<'EOF'
#!/bin/zsh
set -eu
print -rl -- "$@" > "$ARGS_FILE"
[[ $(cat) == 'Task with spaces' ]]
print -u2 -- '{"type":"thread.started","thread_id":"stderr-id"}'
print -r -- '{"type":"item.completed","item":{"text":"session id: message-id"}}'
if [[ ${MOCK_REPLY:-} != no-id ]]; then
  print -r -- '{"type":"thread.started","thread_id":"worker-id"}'
fi
while [[ "$1" != --output-last-message ]]; do shift; done
case ${MOCK_REPLY:-ok} in
  missing) ;;
  empty) : > "$2" ;;
  blank) printf ' \t\n' > "$2" ;;
  *) print -r -- 'Worker summary' > "$2" ;;
esac
exit "${MOCK_EXIT:-0}"
EOF
chmod +x bin/codex

run_worker() {
  local expected=$1 actual=0
  shift
  zsh "$launcher" --spec-file spec.md --summary-file summary.md "$@" > run.log 2>&1 || actual=$?
  if (( actual != expected )); then
    cat run.log >&2
    print -u2 -- "Expected exit $expected, got $actual for $*"
    return 1
  fi
}

expect_args() {
  diff -u <(print -rl -- "$@") "$ARGS_FILE"
}

checkout="${PWD:A}/worker checkout"
output="${PWD:A}/summary.md"
common=(exec --color never)
report=(--json --output-last-message "$output")

run_worker 0
expect_args "${common[@]}" --cd "${PWD:A}" --sandbox workspace-write "${report[@]}" -
[[ $(<summary.md.session-id) == worker-id && $(<summary.md) == 'Worker summary' ]]

run_worker 0 --work-dir "$checkout" --sandbox read-only --worktree
expect_args "${common[@]}" --cd "$checkout" --sandbox read-only --worktree "${report[@]}" -
git -C "$checkout" check-ignore -q .codex-tasks/spec.md
read -r saved_id < summary.md.session-id
run_worker 0 --session-id "$saved_id"
expect_args "${common[@]}" resume "${report[@]}" worker-id -
run_worker 0 --session-id worker-id --work-dir "$checkout" --sandbox read-only
expect_args "${common[@]}" --cd "$checkout" --sandbox read-only resume "${report[@]}" worker-id -
run_worker 0 --resume-last
expect_args "${common[@]}" resume --last "${report[@]}" -

run_worker 0 --sandbox read-only --ephemeral
expect_args "${common[@]}" --cd "${PWD:A}" --sandbox read-only --ephemeral "${report[@]}" -
[[ ! -e summary.md.session-id ]]
run_worker 0
MOCK_REPLY=no-id run_worker 0
[[ ! -e summary.md.session-id ]]

MOCK_REPLY=missing run_worker 1
MOCK_REPLY=empty run_worker 1
MOCK_REPLY=blank run_worker 1
MOCK_EXIT=42 run_worker 42
[[ $(<summary.md.session-id) == worker-id ]]

print -r -- untouched > "$ARGS_FILE"
run_worker 2 --worktree --ephemeral
run_worker 2 --worktree --session-id worker-id
run_worker 2 --worktree --resume-last
[[ $(<"$ARGS_FILE") == untouched ]]
print -r -- 'Launcher regression checks passed.'
