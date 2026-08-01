#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST_MODELS="$ROOT_DIR/bin/list-claude-models"

fail() {
    echo "claude-model-catalog: $*" >&2
    exit 1
}

test_root="$(mktemp -d /private/tmp/jflow-claude-model-catalog.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT
catalog="$test_root/catalog.json"
result="$test_root/result.json"

write_catalog_v1() {
    cat > "$catalog" <<'JSON'
{
  "data": [
    {"id": "gpt-5.6-sol"},
    {"id": "claude-opus-4-8-global"},
    {"id": "us.claude-opus-4-6"},
    {"id": "claude-opus-5"},
    {"id": "us.claude-opus-4-8"},
    {"id": "us.claude-opus-4-7"},
    {"id": "claude-sonnet-5-global"},
    {"id": "claude-sonnet-5"},
    {"id": "claude-sonnet-4-6"},
    {"id": "us.claude-sonnet-4-6"},
    {"id": "us.anthropic.claude-sonnet-4-5-20250929-v1:0"},
    {"id": "claude-haiku-4-5-global"},
    {"id": "us.claude-haiku-4-5"},
    {"id": "us.anthropic.claude-3-5-haiku-20241022-v1:0"}
  ]
}
JSON
}

write_catalog_v1
ANTHROPIC_MODEL="us.claude-opus-4-8" \
ANTHROPIC_SMALL_FAST_MODEL="claude-sonnet-5" \
"$LIST_MODELS" --catalog-file "$catalog" > "$result"

[[ "$(jq -r '.default_model' "$result")" == "us.claude-opus-4-8" ]] ||
    fail "current ANTHROPIC_MODEL must remain the global default"
[[ "$(jq -r '.families.opus.default' "$result")" == "us.claude-opus-4-8" ]] ||
    fail "current Opus model must be the Opus default"
[[ "$(jq -r '.families.sonnet.default' "$result")" == "us.claude-sonnet-4-6" ]] ||
    fail "Sonnet default must prefer the first US route"
[[ "$(jq -r '.families.haiku.default' "$result")" == "us.claude-haiku-4-5" ]] ||
    fail "Haiku default must prefer the first US route"

expected_opus=$'claude-opus-5\nus.claude-opus-4-8\nus.claude-opus-4-7\nus.claude-opus-4-6'
actual_opus="$(jq -r '.families.opus.options[].id' "$result")"
[[ "$actual_opus" == "$expected_opus" ]] ||
    fail "Opus models are not version-descending with US route preference"

expected_sonnet=$'claude-sonnet-5\nus.claude-sonnet-4-6\nus.anthropic.claude-sonnet-4-5-20250929-v1:0'
actual_sonnet="$(jq -r '.families.sonnet.options[].id' "$result")"
[[ "$actual_sonnet" == "$expected_sonnet" ]] ||
    fail "Sonnet models are not version-descending with US route preference"

expected_haiku=$'us.claude-haiku-4-5\nus.anthropic.claude-3-5-haiku-20241022-v1:0'
actual_haiku="$(jq -r '.families.haiku.options[].id' "$result")"
[[ "$actual_haiku" == "$expected_haiku" ]] ||
    fail "Haiku models are not version-descending with US route preference"

for family in opus sonnet haiku; do
    [[ "$(jq -r ".families.$family.options | length" "$result")" -ge 2 ]] ||
        fail "$family must expose at least two options when the gateway provides them"
done

# The deprecated small-fast model must not become the main current/default model.
env -u ANTHROPIC_MODEL \
    ANTHROPIC_SMALL_FAST_MODEL="claude-sonnet-5" \
    "$LIST_MODELS" --catalog-file "$catalog" > "$test_root/no-current.json"
[[ "$(jq -r '.current_model // ""' "$test_root/no-current.json")" == "" ]] ||
    fail "ANTHROPIC_SMALL_FAST_MODEL must not be treated as the current main model"
[[ "$(jq -r '.families.sonnet.default' "$test_root/no-current.json")" == "us.claude-sonnet-4-6" ]] ||
    fail "small-fast model must not override US default selection"
[[ "$(jq -r '.default_model' "$test_root/no-current.json")" == "us.claude-opus-4-8" ]] ||
    fail "without a current model, the global default must prefer a US route"

# Re-reading the same path after its contents change proves the helper has no client cache.
jq '.data += [{"id":"us.claude-opus-6"}]' "$catalog" > "$test_root/catalog-v2.json"
mv "$test_root/catalog-v2.json" "$catalog"
ANTHROPIC_MODEL="us.claude-opus-4-8" \
    "$LIST_MODELS" --catalog-file "$catalog" > "$test_root/refreshed.json"
[[ "$(jq -r '.families.opus.options[0].id' "$test_root/refreshed.json")" == "us.claude-opus-6" ]] ||
    fail "catalog must be read again on every invocation"

# A live request failure falls back only to ANTHROPIC_MODEL and never invents a list.
ANTHROPIC_MODEL="us.claude-opus-4-8" \
    "$LIST_MODELS" \
        --models-url "http://127.0.0.1:1/v1/models" \
        --timeout-seconds 0.2 > "$test_root/fallback.json"
[[ "$(jq -r '.source.type' "$test_root/fallback.json")" == "environment-fallback" ]] ||
    fail "failed live lookup must use the environment fallback"
[[ "$(jq -r '[.families[].options[]] | length' "$test_root/fallback.json")" == "1" ]] ||
    fail "failed live lookup must not use a hard-coded model list"

if grep -Eq 'claude-(opus|sonnet|haiku)-[0-9]' "$LIST_MODELS"; then
    fail "runtime helper must not hard-code versioned Claude model IDs"
fi

echo "claude model catalog ok"
