#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$ROOT_DIR/orchestrate.sh"
FAKE_PROVIDER="$ROOT_DIR/tests/fake-provider"
MAIN_AGENT_UUID="11111111-1111-4111-8111-111111111111"
MAIN_AGENT_RESUME_UUID="33333333-3333-4333-8333-333333333333"
SMOKE_TMP_ROOT="$(mktemp -d /private/tmp/jflow-smoke-suite.XXXXXX)"
trap 'rm -rf "$SMOKE_TMP_ROOT"' EXIT

"$ROOT_DIR/tests/state-contract.sh"
"$ROOT_DIR/tests/noninteractive-runner.sh"
"$ROOT_DIR/tests/main-agent-session.sh"
"$ROOT_DIR/tests/claude-model-catalog.sh"

run_workflow() {
    local scenario="$1"
    local name="$2"
    shift 2

    local tmpdir
    tmpdir="$(mktemp -d "$SMOKE_TMP_ROOT/workflow.XXXXXX")"
    printf 'Smoke requirement for %s.\n' "$name" > "$tmpdir/req.md"

    (
        cd "$tmpdir"
        unset CODEX_THREAD_ID
        export CLAUDE_CODE_SESSION_ID="$MAIN_AGENT_UUID"
        JW_TEST_FORCE_NONINTERACTIVE=1 \
        CLAUDE_BIN="$FAKE_PROVIDER" \
        FAKE_PROVIDER_SCRIPT="$scenario" \
        FAKE_PROVIDER_EXPECT_CWD="$ROOT_DIR" \
        FAKE_PROVIDER_EXPECT_ADD_DIR="$tmpdir/$name" \
        FAKE_PROVIDER_READ_STDIN=1 \
        FAKE_PROVIDER_FAIL_IF_STDIN=1 \
        "$ORCH" \
            --project "$ROOT_DIR" \
            --name "$name" \
            --requirement "$tmpdir/req.md" \
            --workspace "$tmpdir" \
            --provider claude \
            --model fake \
            --auto \
            --break none \
            "$@" \
            > "$tmpdir/out.log" 2>&1
    )

    echo "$tmpdir/$name"
}

assert_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "missing file: $file" >&2
        exit 1
    fi
}

assert_contains() {
    local file="$1"
    local text="$2"
    if ! grep -Fq "$text" "$file"; then
        echo "missing text '$text' in $file" >&2
        exit 1
    fi
}

pass_dir="$(run_workflow pass "jwf-smoke-pass")"
assert_file "$pass_dir/requirement-review/requirement-review.md"
assert_file "$pass_dir/design/plan.md"
assert_file "$pass_dir/design/implementation-brief.md"
assert_file "$pass_dir/review/review.md"
assert_file "$pass_dir/implement/impl-notes.md"
assert_file "$pass_dir/review-code/code-review.md"
assert_file "$pass_dir/verify-observability/observability-report.md"
assert_contains "$pass_dir/requirement-review/requirement-review.md" "VERDICT: PASS"
assert_contains "$pass_dir/review/review.md" "VERDICT: PASS"
assert_contains "$pass_dir/review-code/code-review.md" "VERDICT: PASS"
assert_contains "$pass_dir/verify-observability/observability-report.md" "VERDICT: PASS"
assert_contains "$pass_dir/workflow-state.json" '"provider": "claude"'
assert_contains "$pass_dir/workflow-state.json" "\"session_id\": \"$MAIN_AGENT_UUID\""

repair_dir="$(run_workflow malformed-repair "jwf-smoke-artifact-repair")"
assert_file "$repair_dir/requirement-review/requirement-review.md"
assert_file "$repair_dir/requirement-review/review-requirement.artifact-repair.log"
assert_contains "$repair_dir/requirement-review/requirement-review.md" "审查覆盖与缺口"
assert_contains "$repair_dir/requirement-review/requirement-review.md" "VERDICT: PASS"

pass_tmp="$(dirname "$pass_dir")"
(
    unset CODEX_THREAD_ID
    export CLAUDE_CODE_SESSION_ID="$MAIN_AGENT_RESUME_UUID"
    JW_TEST_FORCE_NONINTERACTIVE=1 \
    CLAUDE_BIN="$FAKE_PROVIDER" \
    FAKE_PROVIDER_SCRIPT=pass \
    "$ORCH" \
        --project "$ROOT_DIR" \
        --name "jwf-smoke-pass" \
        --requirement "$pass_tmp/req.md" \
        --workspace "$pass_tmp" \
        --auto \
        --resume \
        > "$pass_tmp/resume.log" 2>&1
)
assert_contains "$pass_tmp/resume.log" "workflow-state 摘要"
assert_contains "$pass_tmp/resume.log" "last_finished_phase"
assert_contains "$pass_dir/workflow-state.json" "\"session_id\": \"$MAIN_AGENT_RESUME_UUID\""
assert_contains "$pass_dir/workflow-state.json" '"model": "fake"'

timeout_flow_tmp="$(mktemp -d "$SMOKE_TMP_ROOT/flow.XXXXXX")"
"$ROOT_DIR/bin/create-workflow-run" \
    --template "$ROOT_DIR/workflow.json" \
    --output "$timeout_flow_tmp/workflow.json" \
    --mode shell \
    --task-name "jwf-smoke-flow" \
    --provider claude \
    --model fake \
    --max-rounds 3 \
    --phase-timeout-minutes 7 \
    >/dev/null
if [[ "$("$ROOT_DIR/bin/workflow-manifest" execution-get --file "$timeout_flow_tmp/workflow.json" --key phase_timeout_minutes)" != "7" ]]; then
    echo "expected phase_timeout_minutes=7 in run workflow" >&2
    exit 1
fi

interrupt_tmp="$(mktemp -d "$SMOKE_TMP_ROOT/interrupt.XXXXXX")"
printf 'Smoke requirement for signal handling.\n' > "$interrupt_tmp/req.md"
JW_TEST_FORCE_NONINTERACTIVE=1 \
CLAUDE_BIN="$FAKE_PROVIDER" \
FAKE_PROVIDER_SCRIPT=pass \
FAKE_PROVIDER_SLEEP_SECONDS=30 \
"$ORCH" \
    --project "$ROOT_DIR" \
    --name "jwf-smoke-interrupt" \
    --requirement "$interrupt_tmp/req.md" \
    --workspace "$interrupt_tmp" \
    --provider claude \
    --model fake \
    --auto \
    --break none \
    > "$interrupt_tmp/out.log" 2>&1 &
interrupt_pid=$!
interrupt_state="$interrupt_tmp/jwf-smoke-interrupt/workflow-state.json"
interrupt_running=false
for _ in {1..100}; do
    if [[ -f "$interrupt_state" ]] &&
        [[ "$("$ROOT_DIR/bin/workflow-state" get-phase-status --file "$interrupt_state" --phase review-requirement 2>/dev/null || true)" == "running" ]]; then
        interrupt_running=true
        break
    fi
    sleep 0.1
done
if [[ "$interrupt_running" != true ]]; then
    kill -TERM "$interrupt_pid" 2>/dev/null || true
    wait "$interrupt_pid" 2>/dev/null || true
    echo "interrupt smoke never reached running state" >&2
    tail -80 "$interrupt_tmp/out.log" >&2 || true
    exit 1
fi
kill -TERM "$interrupt_pid"
set +e
wait "$interrupt_pid"
interrupt_rc=$?
set -e
if [[ "$interrupt_rc" != "143" ]]; then
    echo "expected interrupted workflow exit 143, got $interrupt_rc" >&2
    exit 1
fi
if [[ "$("$ROOT_DIR/bin/workflow-state" get-phase-status --file "$interrupt_state" --phase review-requirement)" != "failed" ]]; then
    echo "interrupted phase was not marked failed" >&2
    exit 1
fi
if [[ "$("$ROOT_DIR/bin/workflow-state" get-phase-field --file "$interrupt_state" --phase review-requirement --key exit_code)" != "143" ]]; then
    echo "interrupted phase did not record exit code 143" >&2
    exit 1
fi

revise_dir="$(run_workflow review-needs-revision-then-pass "jwf-smoke-revise")"
assert_file "$revise_dir/review/review-r1.md"
assert_file "$revise_dir/review/revise-notes-r1.md"
assert_file "$revise_dir/review/review-r2.md"
assert_contains "$revise_dir/review/review-r1.md" "VERDICT: NEEDS_REVISION"
assert_contains "$revise_dir/review/review-r2.md" "VERDICT: PASS"
assert_contains "$revise_dir/review/review.md" "VERDICT: PASS"

fix_tmp="$(mktemp -d "$SMOKE_TMP_ROOT/fix.XXXXXX")"
printf 'Smoke requirement for max-rounds.\n' > "$fix_tmp/req.md"
set +e
JW_TEST_FORCE_NONINTERACTIVE=1 \
CLAUDE_BIN="$FAKE_PROVIDER" \
FAKE_PROVIDER_SCRIPT=always-needs-fix \
"$ORCH" \
    --project "$ROOT_DIR" \
    --name "jwf-smoke-fix" \
    --requirement "$fix_tmp/req.md" \
    --workspace "$fix_tmp" \
    --provider claude \
    --model fake \
    --auto \
    --break none \
    --max-rounds 1 \
    > "$fix_tmp/out.log" 2>&1
fix_rc=$?
set -e
if [[ "$fix_rc" != "2" ]]; then
    echo "expected max-rounds smoke to exit 2, got $fix_rc" >&2
    tail -80 "$fix_tmp/out.log" >&2 || true
    exit 1
fi
fix_dir="$fix_tmp/jwf-smoke-fix"
assert_file "$fix_dir/review-code/code-review.md"
assert_file "$fix_dir/review-code/fix-notes-r1.md"
assert_contains "$fix_dir/review-code/code-review.md" "VERDICT: NEEDS_FIX"
assert_contains "$fix_dir/workflow-state.json" '"loop_exhausted": "code-review-fix"'

clarify_tmp="$(mktemp -d "$SMOKE_TMP_ROOT/clarify.XXXXXX")"
printf 'Smoke requirement for clarification.\n' > "$clarify_tmp/req.md"
set +e
JW_TEST_FORCE_NONINTERACTIVE=1 \
CLAUDE_BIN="$FAKE_PROVIDER" \
FAKE_PROVIDER_SCRIPT=requirement-needs-clarification \
"$ORCH" \
    --project "$ROOT_DIR" \
    --name "jwf-smoke-clarify" \
    --requirement "$clarify_tmp/req.md" \
    --workspace "$clarify_tmp" \
    --provider claude \
    --model fake \
    --auto \
    --break none \
    > "$clarify_tmp/out.log" 2>&1
clarify_rc=$?
set -e
if [[ "$clarify_rc" != "1" ]]; then
    echo "expected clarification smoke to exit 1, got $clarify_rc" >&2
    tail -80 "$clarify_tmp/out.log" >&2 || true
    exit 1
fi
clarify_dir="$clarify_tmp/jwf-smoke-clarify"
assert_file "$clarify_dir/requirement-review/requirement-review.md"
assert_contains "$clarify_dir/requirement-review/requirement-review.md" "VERDICT: NEEDS_CLARIFICATION"

observability_tmp="$(mktemp -d "$SMOKE_TMP_ROOT/observability.XXXXXX")"
printf 'Smoke requirement for observability.\n' > "$observability_tmp/req.md"
set +e
JW_TEST_FORCE_NONINTERACTIVE=1 \
CLAUDE_BIN="$FAKE_PROVIDER" \
FAKE_PROVIDER_SCRIPT=observability-needs-fix \
"$ORCH" \
    --project "$ROOT_DIR" \
    --name "jwf-smoke-observability" \
    --requirement "$observability_tmp/req.md" \
    --workspace "$observability_tmp" \
    --provider claude \
    --model fake \
    --auto \
    --break none \
    > "$observability_tmp/out.log" 2>&1
observability_rc=$?
set -e
if [[ "$observability_rc" != "1" ]]; then
    echo "expected observability smoke to exit 1, got $observability_rc" >&2
    tail -80 "$observability_tmp/out.log" >&2 || true
    exit 1
fi
observability_dir="$observability_tmp/jwf-smoke-observability"
assert_file "$observability_dir/verify-observability/observability-report.md"
assert_contains "$observability_dir/verify-observability/observability-report.md" "VERDICT: NEEDS_FIX"

echo "smoke ok"
