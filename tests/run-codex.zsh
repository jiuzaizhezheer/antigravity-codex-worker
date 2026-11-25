#!/usr/bin/env zsh
set -euo pipefail

launcher=${0:A:h:h}/scripts/run-codex.zsh
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cd "$test_dir"
mkdir bin
git init -q 'worker checkout'
git -C 'worker checkout' config user.email test@example.com
git -C 'worker checkout' config user.name Tester
git -C 'worker checkout' commit --allow-empty -q -m init
export PATH="$PWD/bin:$PATH" ARGS_FILE="$PWD/args" WORKTREE_BASE="$PWD"
print -r -- 'Task with spaces' > spec.md

cat > bin/codex <<'EOF'
#!/bin/zsh
set -eu
print -rl -- "$@" > "$ARGS_FILE"
[[ $(cat) == 'Task with spaces' ]]
has_worktree=0
work_dir=""
args=("$@")
i=1
while [[ $i -le ${#args[@]} ]]; do
  case "${args[$i]}" in
    --worktree) has_worktree=1 ;;
    --cd)
      if [[ $i -lt ${#args[@]} ]]; then
        work_dir="${args[$((i+1))]}"
      fi
      ;;
  esac
  ((i++))
done
if [[ $has_worktree -eq 1 && -n "$work_dir" ]]; then
  wt_count=${MOCK_WORKTREE_COUNT:-1}
  j=1
  while [[ $j -le $wt_count ]]; do
    wt_dir="$WORKTREE_BASE/wt checkout ${MOCK_WT_TAG:-a}-$j"
    git -C "$work_dir" worktree add -q -b "wt-${MOCK_WT_TAG:-a}-$j" "$wt_dir" >/dev/null 2>&1
    ((j++))
  done
fi
if [[ ${MOCK_STDOUT:-jsonl} == bad-json ]]; then
  print -r -- 'not-valid-json'
elif [[ ${MOCK_STDOUT:-jsonl} == ephemeral ]]; then
  print -r -- 'Ephemeral human output'
else
  print -u2 -- '{"type":"thread.started","thread_id":"stderr-id"}'
  print -r -- '{"type":"item.completed","item":{"text":"session id: message-id"}}'
  if [[ ${MOCK_REPLY:-} != no-id ]]; then
    print -r -- '{"type":"thread.started","thread_id":"worker-id"}'
  fi
  if [[ ${MOCK_EXIT:-0} -ne 0 ]]; then
    print -r -- '{"type":"error","message":"boom"}'
  fi
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
defaults=(--model gpt-6.2-astra -c 'model_reasoning_effort="xhigh"')
report_json=(--json --output-last-message "$output")
report_plain=(--output-last-message "$output")

run_worker 0
expect_args "${common[@]}" --cd "${PWD:A}" --sandbox workspace-write "${defaults[@]}" "${report_json[@]}" -
[[ $(<summary.md.session-id) == worker-id && $(<summary.md) == 'Worker summary' ]]
if grep -qE '"type":"item\.completed"|"thread_id":"worker-id"' run.log; then
  print -u2 -- "Raw JSONL leaked into stdout for persistent run"
  exit 1
fi

run_worker 0 --model custom-model --reasoning-effort low
expect_args "${common[@]}" --cd "${PWD:A}" --sandbox workspace-write --model custom-model -c 'model_reasoning_effort="low"' "${report_json[@]}" -

MOCK_WT_TAG=single run_worker 0 --work-dir "$checkout" --sandbox read-only --worktree
expect_args "${common[@]}" --cd "$checkout" --sandbox read-only --worktree "${defaults[@]}" "${report_json[@]}" -
git -C "$checkout" check-ignore -q .codex-tasks/spec.md
expected_wt="${PWD:A}/wt checkout single-1"
[[ $(<summary.md.worktree) == "$expected_wt" ]]
grep -qF "[CODEX-WORKER] Worktree : $expected_wt" run.log

read -r saved_id < summary.md.session-id
run_worker 0 --session-id "$saved_id"
expect_args "${common[@]}" resume "${defaults[@]}" "${report_json[@]}" worker-id -
[[ ! -e summary.md.worktree ]]
run_worker 0 --session-id worker-id --work-dir "$checkout" --sandbox read-only
expect_args "${common[@]}" --cd "$checkout" --sandbox read-only resume "${defaults[@]}" "${report_json[@]}" worker-id -
run_worker 0 --resume-last
expect_args "${common[@]}" resume --last "${defaults[@]}" "${report_json[@]}" -

MOCK_WT_TAG=multi MOCK_WORKTREE_COUNT=2 run_worker 0 --work-dir "$checkout" --sandbox workspace-write --worktree
[[ ! -e summary.md.worktree ]]
grep -qF "Multiple new worktrees detected" run.log

MOCK_STDOUT=ephemeral run_worker 0 --sandbox read-only --ephemeral
expect_args "${common[@]}" --cd "${PWD:A}" --sandbox read-only --ephemeral "${defaults[@]}" "${report_plain[@]}" -
[[ ! -e summary.md.session-id && ! -e summary.md.worktree ]]
grep -qF 'Ephemeral human output' run.log

run_worker 0
MOCK_REPLY=no-id run_worker 0
[[ ! -e summary.md.session-id ]]

MOCK_STDOUT=bad-json run_worker 0
[[ ! -e summary.md.session-id ]]
if grep -qF 'jq: parse error' run.log; then
  print -u2 -- "jq parse error leaked to output"
  exit 1
fi

MOCK_REPLY=missing run_worker 1
MOCK_REPLY=empty run_worker 1
MOCK_REPLY=blank run_worker 1
MOCK_EXIT=42 run_worker 42
[[ $(<summary.md.session-id) == worker-id ]]
grep -qF 'boom' run.log

print -r -- untouched > "$ARGS_FILE"
run_worker 2 --worktree --ephemeral
run_worker 2 --worktree --session-id worker-id
run_worker 2 --worktree --resume-last
: > summary.md.worktree
zsh "$launcher" --spec-file summary.md.worktree --summary-file summary.md >/dev/null 2>&1 && {
  print -u2 -- "Expected --spec-file summary.md.worktree collision to fail"
  exit 1
} || true
[[ $(<"$ARGS_FILE") == untouched ]]
print -r -- 'Launcher regression checks passed.'
