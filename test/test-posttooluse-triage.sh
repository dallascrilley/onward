#!/bin/bash

# Integration tests for WS-07: PostToolUse triage
# Tests that:
# 1. Disabled mode (default) approves without creating triage
# 2. Exit code 0 (success) does not create triage
# 3. Non-zero exit code creates .claude/triage.md
# 4. Triage contains expected sections
# 5. Heuristic suggestions work for common errors
# 6. Invalid JSON input is handled (fail open)

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
HOOK_SCRIPT="$REPO_ROOT/hooks/claude-posttooluse-triage.sh"

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
echo "WS-07 PostToolUse Triage Tests"
echo "=========================================="
echo ""

# --- Test 1: Disabled by default ---
echo "Test 1: Triage disabled by default (no file created)"

cd "$TEST_PROJECT"
unset REDBULL_TRIAGE_ENABLED

INPUT='{"payload":{"exit_code":1,"command":"test","stderr":"error"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ ! -f ".claude/triage.md" ]]; then
    pass "Disabled mode does not create triage"
else
    fail "Disabled mode does not create triage" "File was created"
fi

# Enable triage for remaining tests
export REDBULL_TRIAGE_ENABLED=true

# --- Test 2: Success (exit 0) does not create triage ---
echo "Test 2: Success (exit 0) does not create triage"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"payload":{"exit_code":0,"command":"echo hello","stdout":"hello"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ ! -f ".claude/triage.md" ]]; then
    pass "Success does not create triage"
else
    fail "Success does not create triage" "File was created for exit 0"
fi

# --- Test 3: Failure creates triage ---
echo "Test 3: Failure (exit 1) creates .claude/triage.md"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"payload":{"exit_code":1,"command":"test-command","stderr":"error message"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    pass "Failure creates triage"
else
    fail "Failure creates triage" "File not created"
fi

# --- Test 4: Triage contains expected sections ---
echo "Test 4: Triage contains expected sections"

if [[ -f ".claude/triage.md" ]]; then
    TRIAGE_CONTENT=$(cat ".claude/triage.md")

    if echo "$TRIAGE_CONTENT" | grep -q "Tool Failure Triage" && \
       echo "$TRIAGE_CONTENT" | grep -q "Exit Code" && \
       echo "$TRIAGE_CONTENT" | grep -q "Command" && \
       echo "$TRIAGE_CONTENT" | grep -q "Error Output" && \
       echo "$TRIAGE_CONTENT" | grep -q "Suggested Next Steps"; then
        pass "Triage contains expected sections"
    else
        fail "Triage contains expected sections" "Missing one or more sections"
    fi
else
    fail "Triage contains expected sections" "Triage file not found"
fi

# --- Test 5: Heuristic - command not found ---
echo "Test 5: Heuristic suggestion for 'command not found'"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"payload":{"exit_code":127,"command":"nonexistent","stderr":"bash: nonexistent: command not found"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    TRIAGE_CONTENT=$(cat ".claude/triage.md")

    if echo "$TRIAGE_CONTENT" | grep -qi "command not found"; then
        pass "Heuristic detects 'command not found'"
    else
        fail "Heuristic detects 'command not found'" "Suggestion not found"
    fi
else
    fail "Heuristic detects 'command not found'" "Triage file not created"
fi

# --- Test 6: Heuristic - permission denied ---
echo "Test 6: Heuristic suggestion for 'permission denied'"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"payload":{"exit_code":1,"command":"./script.sh","stderr":"bash: ./script.sh: Permission denied"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    TRIAGE_CONTENT=$(cat ".claude/triage.md")

    if echo "$TRIAGE_CONTENT" | grep -qi "permission denied"; then
        pass "Heuristic detects 'permission denied'"
    else
        fail "Heuristic detects 'permission denied'" "Suggestion not found"
    fi
else
    fail "Heuristic detects 'permission denied'" "Triage file not created"
fi

# --- Test 7: Heuristic - module not found ---
echo "Test 7: Heuristic suggestion for 'Cannot find module'"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"payload":{"exit_code":1,"command":"node app.js","stderr":"Error: Cannot find module '\''express'\''"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    TRIAGE_CONTENT=$(cat ".claude/triage.md")

    if echo "$TRIAGE_CONTENT" | grep -qi "module not found"; then
        pass "Heuristic detects 'module not found'"
    else
        fail "Heuristic detects 'module not found'" "Suggestion not found"
    fi
else
    fail "Heuristic detects 'module not found'" "Triage file not created"
fi

# --- Test 8: Heuristic - file not found ---
echo "Test 8: Heuristic suggestion for 'No such file or directory'"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"payload":{"exit_code":1,"command":"cat missing.txt","stderr":"cat: missing.txt: No such file or directory"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    TRIAGE_CONTENT=$(cat ".claude/triage.md")

    if echo "$TRIAGE_CONTENT" | grep -qi "file not found"; then
        pass "Heuristic detects 'file not found'"
    else
        fail "Heuristic detects 'file not found'" "Suggestion not found"
    fi
else
    fail "Heuristic detects 'file not found'" "Triage file not created"
fi

# --- Test 9: Heuristic - network error ---
echo "Test 9: Heuristic suggestion for network errors"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"payload":{"exit_code":1,"command":"curl https://api.example.com","stderr":"curl: (7) Failed to connect to api.example.com port 443: Connection refused"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    TRIAGE_CONTENT=$(cat ".claude/triage.md")

    if echo "$TRIAGE_CONTENT" | grep -qi "network error"; then
        pass "Heuristic detects network error"
    else
        fail "Heuristic detects network error" "Suggestion not found"
    fi
else
    fail "Heuristic detects network error" "Triage file not created"
fi

# --- Test 10: Heuristic - syntax error ---
echo "Test 10: Heuristic suggestion for syntax errors"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"payload":{"exit_code":1,"command":"node app.js","stderr":"SyntaxError: Unexpected token"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    TRIAGE_CONTENT=$(cat ".claude/triage.md")

    if echo "$TRIAGE_CONTENT" | grep -qi "syntax error"; then
        pass "Heuristic detects syntax error"
    else
        fail "Heuristic detects syntax error" "Suggestion not found"
    fi
else
    fail "Heuristic detects syntax error" "Triage file not created"
fi

# --- Test 11: Generic suggestion for unknown errors ---
echo "Test 11: Generic suggestion for unknown error patterns"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"payload":{"exit_code":42,"command":"unknown-tool","stderr":"Some obscure error message"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    TRIAGE_CONTENT=$(cat ".claude/triage.md")

    if echo "$TRIAGE_CONTENT" | grep -qi "generic failure"; then
        pass "Generic suggestion provided for unknown error"
    else
        fail "Generic suggestion provided for unknown error" "Default suggestion not found"
    fi
else
    fail "Generic suggestion provided for unknown error" "Triage file not created"
fi

# --- Test 12: Invalid JSON input (fail open) ---
echo "Test 12: Invalid JSON input handled (fail open)"

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

# --- Test 13: Extract from alternate payload paths ---
echo "Test 13: Extract exit code from tool_result.exit_code"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

INPUT='{"tool_result":{"exit_code":1,"command":"test","stderr":"error"}}'
echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    pass "Extracts exit code from tool_result path"
else
    fail "Extracts exit code from tool_result path" "Triage not created"
fi

# --- Test 14: Output truncation (max 40 lines) ---
echo "Test 14: Error output truncated to max lines"

rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Create stderr with >40 lines
LONG_STDERR=$(for i in $(seq 1 60); do echo "Error line $i"; done)

INPUT=$(jq -n \
    --arg stderr "$LONG_STDERR" \
    '{payload: {exit_code: 1, command: "test", stderr: $stderr}}')

echo "$INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f ".claude/triage.md" ]]; then
    TRIAGE_CONTENT=$(cat ".claude/triage.md")

    # Should contain "Error line 1" and "Error line 40" but not "Error line 50"
    if echo "$TRIAGE_CONTENT" | grep -q "Error line 1" && \
       echo "$TRIAGE_CONTENT" | grep -q "Error line 40" && \
       ! echo "$TRIAGE_CONTENT" | grep -q "Error line 50"; then
        pass "Error output truncated to max lines"
    else
        fail "Error output truncated to max lines" "Truncation did not work as expected"
    fi
else
    fail "Error output truncated to max lines" "Triage file not created"
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
