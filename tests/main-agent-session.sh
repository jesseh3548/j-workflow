#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$ROOT_DIR/bin/detect-main-agent-session"
CLAUDE_UUID="11111111-1111-4111-8111-111111111111"
CODEX_UUID="22222222-2222-4222-8222-222222222222"

fail() {
    echo "main-agent-session: $*" >&2
    exit 1
}

claude_result="$(
    env -u CODEX_THREAD_ID \
        CLAUDE_CODE_SESSION_ID="$CLAUDE_UUID" \
        "$DETECT"
)"
[[ "$claude_result" == $'claude\t'"$CLAUDE_UUID" ]] ||
    fail "Claude main session was not detected"

codex_result="$(
    env -u CLAUDE_CODE_SESSION_ID \
        CODEX_THREAD_ID="$CODEX_UUID" \
        "$DETECT"
)"
[[ "$codex_result" == $'codex\t'"$CODEX_UUID" ]] ||
    fail "Codex main session was not detected"

set +e
env \
    CLAUDE_CODE_SESSION_ID="$CLAUDE_UUID" \
    CODEX_THREAD_ID="$CODEX_UUID" \
    "$DETECT" >/dev/null 2>&1
ambiguous_rc=$?
set -e
[[ "$ambiguous_rc" == "2" ]] ||
    fail "ambiguous main sessions must be rejected"

nested_claude_result="$(
    CLAUDECODE=1 \
    CLAUDE_CODE_SESSION_ID="$CLAUDE_UUID" \
    CODEX_THREAD_ID="$CODEX_UUID" \
    "$DETECT"
)"
[[ "$nested_claude_result" == $'claude\t'"$CLAUDE_UUID" ]] ||
    fail "Claude runtime marker must win over an inherited Codex thread ID"

explicit_result="$(
    CLAUDE_CODE_SESSION_ID="$CLAUDE_UUID" \
    CODEX_THREAD_ID="$CODEX_UUID" \
    JFLOW_MAIN_AGENT_PROVIDER=codex \
    JFLOW_MAIN_AGENT_SESSION_ID="$CODEX_UUID" \
    "$DETECT"
)"
[[ "$explicit_result" == $'codex\t'"$CODEX_UUID" ]] ||
    fail "explicit main session override was not honored"

echo "main agent session ok"
