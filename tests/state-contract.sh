#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_BIN="$ROOT_DIR/bin/workflow-state"
VALIDATOR="$ROOT_DIR/bin/validate-workflow-state"
CREATE_RUN="$ROOT_DIR/bin/create-workflow-run"
MANIFEST_BIN="$ROOT_DIR/bin/workflow-manifest"

fail() {
    echo "state-contract: $*" >&2
    exit 1
}

assert_status() {
    local state_file="$1"
    local phase="$2"
    local expected="$3"
    local actual
    actual="$($STATE_BIN get-phase-status --file "$state_file" --phase "$phase")"
    [[ "$actual" == "$expected" ]] || fail "expected $phase status=$expected, got ${actual:-<empty>}"
}

test_root="$(mktemp -d /private/tmp/jflow-state-contract.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT
flow_file="$test_root/workflow.json"
state_file="$test_root/workflow-state.json"

$CREATE_RUN \
    --template "$ROOT_DIR/workflow.json" \
    --output "$flow_file" \
    --mode shell \
    --task-name state-contract \
    --provider claude \
    --model fake \
    >/dev/null
[[ "$($MANIFEST_BIN root-get --file "$flow_file" --key provider)" == "claude" ]] ||
    fail "run workflow provider getter mismatch"
[[ "$($MANIFEST_BIN root-get --file "$flow_file" --key model)" == "fake" ]] ||
    fail "run workflow model getter mismatch"

invalid_manifest="$test_root/invalid-workflow.json"
mkdir -p "$test_root/prompts"
cp "$ROOT_DIR"/prompts/*.md "$test_root/prompts/"
awk '
    !changed && /"id": "explore"/ {
        sub(/"id": "explore"/, "\"id\": \"Explore\"")
        changed = 1
    }
    { print }
' "$ROOT_DIR/workflow.json" > "$invalid_manifest"
if "$ROOT_DIR/bin/validate-workflow-manifest" "$invalid_manifest"; then
    fail "manifest phase IDs must be lowercase kebab-case"
fi

$STATE_BIN init \
    --file "$state_file" \
    --workflow-id state-contract \
    --task-name state-contract \
    --provider claude \
    --model fake \
    --project-dir "$ROOT_DIR" \
    --workspace-dir "$test_root"
$STATE_BIN set-workflow-meta --file "$state_file" --key flow_file --value "$flow_file"
$STATE_BIN set-main-agent \
    --file "$state_file" \
    --provider claude \
    --session-id 11111111-1111-4111-8111-111111111111
[[ "$($STATE_BIN get-main-agent-provider --file "$state_file")" == "claude" ]] ||
    fail "main agent provider getter mismatch"
[[ "$($STATE_BIN get-main-agent-session-id --file "$state_file")" == "11111111-1111-4111-8111-111111111111" ]] ||
    fail "main agent session getter mismatch"
if $STATE_BIN set-main-agent \
    --file "$state_file" \
    --provider claude \
    --session-id not-a-uuid; then
    fail "main agent session id must be UUID-shaped"
fi

# A canonical non-loop phase can be started and completed without the agent
# providing a phase key.
$STATE_BIN phase-start \
    --file "$state_file" \
    --phase implement \
    --provider claude \
    --model fake \
    --session-name state-contract-implement \
    --output-file "$test_root/impl-notes.md" \
    --prompt-file "$test_root/implement.prompt" \
    --run-script "$test_root/implement.run.sh" \
    --started-epoch 0
$STATE_BIN set-workflow-meta --file "$state_file" --key current_phase --value implement

if $STATE_BIN phase-finish \
    --file "$state_file" \
    --phase Implement \
    --status done \
    --exit-code 0 \
    --output-file "$test_root/impl-notes.md"; then
    fail "case-mismatched phase finish must be rejected"
fi
if grep -Fq '"Implement"' "$state_file"; then
    fail "case-mismatched phase finish must not create a ghost phase"
fi

$STATE_BIN phase-finish-active \
    --file "$state_file" \
    --status done \
    --exit-code 0 \
    --output-file "$test_root/impl-notes.md"
assert_status "$state_file" implement done

# Loop instances must match the current manifest template exactly.
for invalid_phase in Revise revise-r0 revise-rx; do
    if $STATE_BIN phase-start \
        --file "$state_file" \
        --phase "$invalid_phase" \
        --provider claude \
        --model fake \
        --session-name "state-contract-$invalid_phase" \
        --output-file "$test_root/$invalid_phase.md" \
        --prompt-file "$test_root/$invalid_phase.prompt" \
        --run-script "$test_root/$invalid_phase.run.sh" \
        --started-epoch 0; then
        fail "invalid phase instance $invalid_phase must be rejected"
    fi
done

$STATE_BIN phase-start \
    --file "$state_file" \
    --phase revise-r1 \
    --provider claude \
    --model fake \
    --session-name state-contract-revise-r1 \
    --output-file "$test_root/revise-r1.md" \
    --prompt-file "$test_root/revise-r1.prompt" \
    --run-script "$test_root/revise-r1.run.sh" \
    --started-epoch 0
$VALIDATOR --manifest "$flow_file" "$state_file"
grep -Fq '"session_id": "11111111-1111-4111-8111-111111111111"' "$state_file" ||
    fail "main agent UUID was not persisted"

echo "state contract ok"
