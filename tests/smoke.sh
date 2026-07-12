#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$ROOT_DIR/orchestrate.sh"
FAKE_PROVIDER="$ROOT_DIR/tests/fake-provider"

run_workflow() {
    local scenario="$1"
    local name="$2"
    shift 2

    local tmpdir
    tmpdir="$(mktemp -d /tmp/jwf-smoke.XXXXXX)"
    printf 'Smoke requirement for %s.\n' "$name" > "$tmpdir/req.md"

    JW_TEST_FORCE_NONINTERACTIVE=1 \
    CLAUDE_BIN="$FAKE_PROVIDER" \
    FAKE_PROVIDER_SCRIPT="$scenario" \
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
assert_file "$pass_dir/design/plan.md"
assert_file "$pass_dir/design/implementation-brief.md"
assert_file "$pass_dir/review/review.md"
assert_file "$pass_dir/implement/impl-notes.md"
assert_file "$pass_dir/review-code/code-review.md"
assert_contains "$pass_dir/review/review.md" "VERDICT: PASS"
assert_contains "$pass_dir/review-code/code-review.md" "VERDICT: PASS"

revise_dir="$(run_workflow review-needs-revision-then-pass "jwf-smoke-revise")"
assert_file "$revise_dir/review/review-r1.md"
assert_file "$revise_dir/review/revise-notes-r1.md"
assert_file "$revise_dir/review/review-r2.md"
assert_contains "$revise_dir/review/review-r1.md" "VERDICT: NEEDS_REVISION"
assert_contains "$revise_dir/review/review-r2.md" "VERDICT: PASS"
assert_contains "$revise_dir/review/review.md" "VERDICT: PASS"

fix_tmp="$(mktemp -d /tmp/jwf-smoke-fix.XXXXXX)"
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

echo "smoke ok"
