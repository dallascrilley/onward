#!/bin/bash

# Snapshot test for prompt/schema stability
# Fails if current prompt/schema differs from stored snapshot
# Run: ./test/test-snapshot.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/claude-judge-continuation.sh"
SNAPSHOT_DIR="$SCRIPT_DIR/snapshots"
FIXTURE_TRANSCRIPT="$SNAPSHOT_DIR/fixture-transcript.ndjson"
SNAPSHOT_FILE="$SNAPSHOT_DIR/prompt-schema.snapshot.json"

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

# Validate prerequisites
[ -x "$HOOK_SCRIPT" ] || fail "Hook script not found or not executable: $HOOK_SCRIPT"
[ -f "$FIXTURE_TRANSCRIPT" ] || fail "Fixture transcript not found: $FIXTURE_TRANSCRIPT"
[ -f "$SNAPSHOT_FILE" ] || fail "Snapshot file not found: $SNAPSHOT_FILE (run ./test/test-snapshot-update.sh to create)"

# Generate current prompt/schema
hook_event=$(jq -n --arg path "$FIXTURE_TRANSCRIPT" '{"transcript_path": $path, "session_id": "snapshot-test"}')

# Run hook in extraction mode
current_output=$(echo "$hook_event" | SNAPSHOT_EXTRACT_MODE=true "$HOOK_SCRIPT" 2>/dev/null)
exit_code=$?

[ $exit_code -eq 0 ] || fail "Hook extraction failed with exit code $exit_code"

# Validate output is JSON
echo "$current_output" | jq -e '.' > /dev/null 2>&1 || fail "Hook extraction produced invalid JSON"

# Compare with snapshot (normalize JSON for comparison)
current_normalized=$(echo "$current_output" | jq -S '.')
snapshot_normalized=$(jq -S '.' "$SNAPSHOT_FILE")

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
