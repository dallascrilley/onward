#!/bin/bash

# A CDPATH inherited from the caller makes `cd` echo its destination, which
# would corrupt every path resolved through a cd subshell below.
unset CDPATH

# Test: DoD prompt injection and enforcement wording
# Verifies snapshot extraction includes DoD section with strict/advisory semantics.

set -euo pipefail

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/claude-judge-continuation.sh"
FIXTURE_TRANSCRIPT="$SCRIPT_DIR/snapshots/fixture-transcript.ndjson"

require_cmd jq
[ -x "$HOOK_SCRIPT" ] || fail "Hook script not found or not executable: $HOOK_SCRIPT"
[ -f "$FIXTURE_TRANSCRIPT" ] || fail "Fixture transcript not found: $FIXTURE_TRANSCRIPT"

TEMP_DIR="$(mktemp -d "/tmp/onward-dod-prompt-XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

run_extraction() {
    local enforcement="$1"
    local settings_dir="$TEMP_DIR/$enforcement/.claude"
    local settings_path="$settings_dir/onward.local.md"
    mkdir -p "$settings_dir"

    cat > "$settings_path" <<EOF
---
enabled: true
aggressiveness: high
dod_enforcement: $enforcement
definition_of_done:
  - "All tests pass"
  - "CHANGELOG.md updated"
---
EOF

    local hook_event
    hook_event=$(jq -n --arg path "$FIXTURE_TRANSCRIPT" '{"transcript_path": $path, "session_id": "snapshot-dod-test"}')

    echo "$hook_event" | \
        ONWARD_SETTINGS_PATH="$settings_path" \
        SNAPSHOT_EXTRACT_MODE=true \
        SNAPSHOT_EXTRACT_ALLOW=true \
        "$HOOK_SCRIPT"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if ! printf '%s' "$haystack" | grep -Fq "$needle"; then
        fail "Expected prompt to include: $needle"
    fi
}

# Strict mode expectations
strict_output=$(run_extraction "strict")
strict_prompt=$(echo "$strict_output" | jq -r '.evaluation_prompt')
assert_contains "$strict_prompt" "DEFINITION OF DONE"
assert_contains "$strict_prompt" "Only approve STOP if"
assert_contains "$strict_prompt" "unresolvable blocker"
assert_contains "$strict_prompt" "evidence"
assert_contains "$strict_prompt" "All tests pass"

# Advisory mode expectations
advisory_output=$(run_extraction "advisory")
advisory_prompt=$(echo "$advisory_output" | jq -r '.evaluation_prompt')
assert_contains "$advisory_prompt" "DEFINITION OF DONE"
assert_contains "$advisory_prompt" "Default to STOP when uncertain"
assert_contains "$advisory_prompt" "lean toward continuing"
assert_contains "$advisory_prompt" "CHANGELOG.md updated"

echo "PASS: DoD prompt injection and enforcement wording"
