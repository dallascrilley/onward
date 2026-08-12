#!/bin/bash

# A CDPATH inherited from the caller makes `cd` echo its destination, which
# would corrupt every path resolved through a cd subshell below.
unset CDPATH

# Integration tests for WS-06: SessionStart brief
# Tests that:
# 1. Disabled mode (default) approves without creating brief
# 2. Enabled mode creates .claude/session-brief.md
# 3. Brief contains expected sections
# 4. Missing files are handled gracefully
# 5. Invalid JSON input is handled (fail open)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$REPO_ROOT/hooks/claude-sessionstart-brief.sh"

# Test isolation
TEST_PROJECT=$(mktemp -d)
ORIGINAL_PWD="$PWD"

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_PROJECT"
    cd "$ORIGINAL_PWD"
}
trap cleanup EXIT

# Helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo "  Details: $2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

echo "=========================================="
echo "WS-06 SessionStart Brief Tests"
echo "=========================================="
echo ""

# --- Test 1: Disabled by default ---
echo "Test 1: Brief disabled by default (no file created)"

cd "$TEST_PROJECT"
unset ONWARD_SESSION_BRIEF_ENABLED

INPUT='{"session_id":"test-001"}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ ! -f ".claude/session-brief.md" ]]; then
    pass "Disabled mode does not create brief"
else
    fail "Disabled mode does not create brief" "File was created"
fi

# --- Test 2: Enabled mode creates brief ---
echo "Test 2: Enabled mode creates .claude/session-brief.md"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

export ONWARD_SESSION_BRIEF_ENABLED=true

INPUT='{"session_id":"test-002"}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/session-brief.md" ]]; then
    pass "Enabled mode creates brief"
else
    fail "Enabled mode creates brief" "File not created"
fi

# --- Test 3: Brief contains expected sections ---
echo "Test 3: Brief contains expected sections"

if [[ -f ".claude/session-brief.md" ]]; then
    BRIEF_CONTENT=$(cat ".claude/session-brief.md")

    if echo "$BRIEF_CONTENT" | grep -q "Session Brief" && \
       echo "$BRIEF_CONTENT" | grep -q "Key Commands" && \
       echo "$BRIEF_CONTENT" | grep -q "Quality Gates" && \
       echo "$BRIEF_CONTENT" | grep -q "Notes & Gotchas"; then
        pass "Brief contains expected sections"
    else
        fail "Brief contains expected sections" "Missing one or more sections"
    fi
else
    fail "Brief contains expected sections" "Brief file not found"
fi

# --- Test 4: Brief includes stub file content ---
echo "Test 4: Brief includes content from stub files"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Create stub files
echo "# Project README" > README.md
echo "# Agent Instructions" > AGENTS.md
echo "# Claude Instructions" > CLAUDE.md

INPUT='{"session_id":"test-003"}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/session-brief.md" ]]; then
    BRIEF_CONTENT=$(cat ".claude/session-brief.md")

    if echo "$BRIEF_CONTENT" | grep -q "Project README" && \
       echo "$BRIEF_CONTENT" | grep -q "Agent Instructions" && \
       echo "$BRIEF_CONTENT" | grep -q "Claude Instructions"; then
        pass "Brief includes stub file content"
    else
        fail "Brief includes stub file content" "Content not found in brief"
    fi
else
    fail "Brief includes stub file content" "Brief file not created"
fi

# --- Test 5: Missing files handled gracefully ---
echo "Test 5: Missing files handled gracefully"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# No stub files created
INPUT='{"session_id":"test-004"}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/session-brief.md" ]]; then
    BRIEF_CONTENT=$(cat ".claude/session-brief.md")

    # Should still have Key Commands and Quality Gates sections
    if echo "$BRIEF_CONTENT" | grep -q "Key Commands" && \
       echo "$BRIEF_CONTENT" | grep -q "Quality Gates"; then
        pass "Missing files handled gracefully"
    else
        fail "Missing files handled gracefully" "Brief missing expected sections"
    fi
else
    fail "Missing files handled gracefully" "Brief file not created"
fi

# --- Test 6: Invalid JSON input (fail open) ---
echo "Test 6: Invalid JSON input handled (fail open)"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

OUTPUT=$(echo "not json" | "$HOOK_SCRIPT" 2>/dev/null)
DECISION=$(echo "$OUTPUT" | jq -r '.decision // "unknown"')

if [ "$DECISION" = "approve" ]; then
    pass "Invalid JSON handled (fail open)"
else
    fail "Invalid JSON handled (fail open)" "Got decision: $DECISION"
fi

# --- Test 7: PLAN-OVERVIEW.md detection ---
echo "Test 7: Newest PLAN-OVERVIEW.md included if present"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT/docs/plans/feature-x"
cd "$TEST_PROJECT"

echo "# Feature X Plan" > "docs/plans/feature-x/PLAN-OVERVIEW.md"

INPUT='{"session_id":"test-005"}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/session-brief.md" ]]; then
    BRIEF_CONTENT=$(cat ".claude/session-brief.md")

    if echo "$BRIEF_CONTENT" | grep -q "Feature X Plan"; then
        pass "PLAN-OVERVIEW.md detected and included"
    else
        fail "PLAN-OVERVIEW.md detected and included" "Plan content not found"
    fi
else
    fail "PLAN-OVERVIEW.md detected and included" "Brief file not created"
fi

# --- Test 8: Line truncation (max 60 lines per file) ---
echo "Test 8: File content truncated to max lines"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Create a file with >60 lines
{
    for i in $(seq 1 100); do
        echo "Line $i"
    done
} > README.md

INPUT='{"session_id":"test-006"}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/session-brief.md" ]]; then
    BRIEF_CONTENT=$(cat ".claude/session-brief.md")

    # Should contain "Line 1" and "Line 60" but not "Line 70"
    if echo "$BRIEF_CONTENT" | grep -q "Line 1" && \
       echo "$BRIEF_CONTENT" | grep -q "Line 60" && \
       ! echo "$BRIEF_CONTENT" | grep -q "Line 70"; then
        pass "File content truncated to max lines"
    else
        fail "File content truncated to max lines" "Truncation did not work as expected"
    fi
else
    fail "File content truncated to max lines" "Brief file not created"
fi

# --- Summary ---
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Total:  $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    exit 1
else
    echo -e "Failed: 0"
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
