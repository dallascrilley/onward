#!/bin/bash

# Regenerates the prompt/schema snapshot from current hook implementation
# Run this intentionally when prompts are changed
# Usage: ./test/test-snapshot-update.sh

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

# Validate prerequisites
command -v jq >/dev/null 2>&1 || { echo -e "${RED}ERROR: Missing required command: jq${NC}" >&2; exit 1; }
[ -x "$HOOK_SCRIPT" ] || { echo -e "${RED}ERROR: Hook script not found or not executable: $HOOK_SCRIPT${NC}" >&2; exit 1; }
[ -f "$FIXTURE_TRANSCRIPT" ] || { echo -e "${RED}ERROR: Fixture transcript not found: $FIXTURE_TRANSCRIPT${NC}" >&2; exit 1; }

# Ensure snapshot directory exists
mkdir -p "$SNAPSHOT_DIR"

# Generate hook event
hook_event=$(jq -n --arg path "$FIXTURE_TRANSCRIPT" '{"transcript_path": $path, "session_id": "snapshot-update"}')

# Extract current prompt/schema (capture stderr for diagnostics)
stderr_file=$(mktemp)
trap "rm -f '$stderr_file'" EXIT

set +e
new_snapshot=$(echo "$hook_event" | SNAPSHOT_EXTRACT_MODE=true SNAPSHOT_EXTRACT_ALLOW=true "$HOOK_SCRIPT" 2>"$stderr_file")
hook_exit=$?
set -e

if [ $hook_exit -ne 0 ]; then
    echo -e "${RED}ERROR: Hook extraction failed with exit code $hook_exit${NC}" >&2
    [ -s "$stderr_file" ] && cat "$stderr_file" >&2
    exit 1
fi

if ! echo "$new_snapshot" | jq -e '.' > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Hook extraction produced invalid JSON${NC}" >&2
    echo "$new_snapshot" >&2
    [ -s "$stderr_file" ] && echo "Hook stderr:" >&2 && cat "$stderr_file" >&2
    exit 1
fi

# Write formatted snapshot
echo "$new_snapshot" | jq '.' > "$SNAPSHOT_FILE"

echo -e "${GREEN}Snapshot updated: $SNAPSHOT_FILE${NC}"
echo ""
echo -e "${YELLOW}Review the changes and run evals before committing:${NC}"
echo "  git diff $SNAPSHOT_FILE"
echo "  ./test/evals/run-evals.sh"
