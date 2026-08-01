#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/bin/run-provider-noninteractive"
FAKE_PROVIDER="$ROOT_DIR/tests/fake-provider"

fail() {
    echo "noninteractive-runner: $*" >&2
    exit 1
}

test_root="$(mktemp -d /private/tmp/jflow-noninteractive-runner.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT
project_dir="$test_root/project"
workspace_dir="$test_root/workspace"
mkdir -p "$project_dir" "$workspace_dir"
printf 'runner contract test\n' > "$test_root/prompt"

# Claude must run from --project-dir, receive --workspace-dir via --add-dir,
# and see EOF rather than inheriting the orchestrator's phase-list stdin.
printf 'next-phase-must-not-be-consumed\n' |
    FAKE_PROVIDER_EXPECT_CWD="$project_dir" \
    FAKE_PROVIDER_EXPECT_ADD_DIR="$workspace_dir" \
    FAKE_PROVIDER_READ_STDIN=1 \
    FAKE_PROVIDER_FAIL_IF_STDIN=1 \
    "$RUNNER" \
        --provider claude \
        --provider-cli "$FAKE_PROVIDER" \
        --model fake \
        --project-dir "$project_dir" \
        --workspace-dir "$workspace_dir" \
        --prompt-file "$test_root/prompt" \
        --log-file "$test_root/pass.log" \
        --timeout-seconds 0

set +e
FAKE_PROVIDER_SLEEP_SECONDS=5 \
"$RUNNER" \
    --provider claude \
    --provider-cli "$FAKE_PROVIDER" \
    --model fake \
    --project-dir "$project_dir" \
    --workspace-dir "$workspace_dir" \
    --prompt-file "$test_root/prompt" \
    --log-file "$test_root/timeout.log" \
    --timeout-seconds 1
timeout_rc=$?
set -e

[[ "$timeout_rc" == "124" ]] || fail "expected timeout exit 124, got $timeout_rc"
grep -Fq "provider timed out after 1 seconds" "$test_root/timeout.log" ||
    fail "timeout log is missing the timeout diagnostic"

echo "noninteractive runner ok"
