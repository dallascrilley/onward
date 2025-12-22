#!/bin/bash

# Verify malformed hook event JSON fails closed with a clear approve decision.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/claude-judge-continuation.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    exit 1
}

pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
}

# Pseudocode:
# - send malformed JSON to the hook
# - ensure the hook returns valid JSON
# - assert decision is "approve"
# - assert reason mentions invalid JSON
# - report pass/fail

INVALID_EVENT='{not-json'
HOOK_OUTPUT=$(printf '%s' "$INVALID_EVENT" | "$HOOK_SCRIPT")

if ! echo "$HOOK_OUTPUT" | jq -e '.' >/dev/null 2>&1; then
    fail "hook output is not valid JSON"
fi

DECISION=$(echo "$HOOK_OUTPUT" | jq -r '.decision // empty')
REASON=$(echo "$HOOK_OUTPUT" | jq -r '.reason // empty')

if [ "$DECISION" != "approve" ]; then
    fail "expected decision approve, got \"$DECISION\""
fi

case "$REASON" in
    *"Invalid JSON input"*)
        pass "invalid JSON input returns approve with clear reason"
        ;;
    *)
        fail "expected invalid JSON reason, got \"$REASON\""
        ;;
esac
