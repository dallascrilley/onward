#!/bin/bash

# A CDPATH inherited from the caller makes `cd` echo its destination, which
# would corrupt every path resolved through a cd subshell below.
unset CDPATH

# Snapshot test for prompt/schema stability
# Fails if current prompt/schema differs from stored snapshot
# Run: ./test/test-snapshot.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

fail() {
    echo -e "${RED}FAIL: $1${NC}" >&2
    exit 1
}

pass() {
    echo -e "${GREEN}PASS: $1${NC}"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script_dir_exit=$?
set -e
[ $script_dir_exit -eq 0 ] || fail "Failed to resolve script directory"

HOOK_SCRIPT="$SCRIPT_DIR/../hooks/claude-judge-continuation.sh"
SNAPSHOT_DIR="$SCRIPT_DIR/snapshots"
FIXTURE_TRANSCRIPT="$SNAPSHOT_DIR/fixture-transcript.ndjson"
SNAPSHOT_FILE="$SNAPSHOT_DIR/prompt-schema.snapshot.json"

# Validate prerequisites
require_cmd jq
[ -x "$HOOK_SCRIPT" ] || fail "Hook script not found or not executable: $HOOK_SCRIPT"
[ -f "$FIXTURE_TRANSCRIPT" ] || fail "Fixture transcript not found: $FIXTURE_TRANSCRIPT"
[ -f "$SNAPSHOT_FILE" ] || fail "Snapshot file not found: $SNAPSHOT_FILE (run ./test/test-snapshot-update.sh to create)"

# Generate current prompt/schema
set +e
hook_event=$(jq -n --arg path "$FIXTURE_TRANSCRIPT" '{"transcript_path": $path, "session_id": "snapshot-test"}')
hook_event_exit=$?
set -e
[ $hook_event_exit -eq 0 ] || fail "Failed to build hook event JSON"

# Run hook in extraction mode
set +e
current_output=$(echo "$hook_event" | SNAPSHOT_EXTRACT_MODE=true SNAPSHOT_EXTRACT_ALLOW=true "$HOOK_SCRIPT")
exit_code=$?
set -e

[ $exit_code -eq 0 ] || fail "Hook extraction failed with exit code $exit_code"

# Validate output is JSON
echo "$current_output" | jq -e '.' > /dev/null 2>&1 || fail "Hook extraction produced invalid JSON"

# Compare with snapshot (normalize JSON for comparison)
set +e
current_normalized=$(echo "$current_output" | jq -S '.')
current_norm_exit=$?
set -e
[ $current_norm_exit -eq 0 ] || fail "Failed to normalize hook output JSON"

set +e
snapshot_normalized=$(jq -S '.' "$SNAPSHOT_FILE")
snapshot_norm_exit=$?
set -e
[ $snapshot_norm_exit -eq 0 ] || fail "Failed to normalize snapshot JSON"

if [ "$current_normalized" = "$snapshot_normalized" ]; then
    pass "Prompt/schema matches snapshot"
    exit 0
else
    echo -e "${RED}FAIL: Prompt/schema has changed${NC}" >&2
    echo ""
    echo "Diff (expected vs actual):"
    diff <(echo "$snapshot_normalized") <(echo "$current_normalized") || true
    echo ""
    echo -e "${YELLOW}To update snapshot: ./test/test-snapshot-update.sh${NC}"
    exit 1
fi
