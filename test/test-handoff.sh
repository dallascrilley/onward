#!/bin/bash

# Integration tests for WS-04: Handoff snapshot on approved stop
# Tests that:
# 1. Approved stop creates .claude/handoff.md
# 2. Blocked stop does NOT create handoff
# 3. Handoff contains required sections
# 4. Git info included when in git repo
# 5. Judge mode skips handoff creation

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
HOOK_SCRIPT="$REPO_ROOT/hooks/claude-judge-continuation.sh"
HANDOFF_LIB="$REPO_ROOT/hooks/lib/handoff.sh"

# Test isolation
TEST_HOME=$(mktemp -d)
TEST_PROJECT=$(mktemp -d)
ORIGINAL_HOME="$HOME"
ORIGINAL_PWD="$PWD"

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_HOME" "$TEST_PROJECT"
    export HOME="$ORIGINAL_HOME"
    cd "$ORIGINAL_PWD"
}
trap cleanup EXIT

# Switch to test home and project
export HOME="$TEST_HOME"

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

skip() {
    echo -e "${YELLOW}○ SKIP${NC}: $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Create a mock transcript file for testing
create_mock_transcript() {
    local transcript_file="$1"
    cat > "$transcript_file" << 'EOF'
{"role": "user", "content": "Create a simple function"}
{"role": "assistant", "content": "I'll create a simple function for you. Done!"}
EOF
}

# Setup stub claude that returns approve/block based on env var
setup_stub_claude() {
    local decision="${1:-false}"  # false = approve stop, true = continue
    mkdir -p "$TEST_HOME/bin"
    cat > "$TEST_HOME/bin/claude" << STUB
#!/bin/bash
cat >/dev/null  # consume stdin
echo '[{"type":"result","structured_output":{"should_continue":$decision,"reasoning":"Test decision"}}]'
STUB
    chmod +x "$TEST_HOME/bin/claude"
    export PATH="$TEST_HOME/bin:$PATH"
}

echo "=========================================="
echo "WS-04 Handoff Snapshot Integration Tests"
echo "=========================================="
echo ""

# --- Test 1: Approved stop creates handoff.md ---
echo "Test 1: Approved stop creates .claude/handoff.md"

# Setup fresh project directory
rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Create decision dir for the hook
mkdir -p "$TEST_HOME/.claude/redbull"

# Create transcript
TRANSCRIPT_FILE="$TEST_PROJECT/transcript.ndjson"
create_mock_transcript "$TRANSCRIPT_FILE"

# Setup stub that approves stop
setup_stub_claude "false"

# Run hook
HOOK_INPUT='{"session_id":"test-handoff-001","transcript_path":"'"$TRANSCRIPT_FILE"'","stop_hook_active":false}'
echo "$HOOK_INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1 || true

if [[ -f "$TEST_PROJECT/.claude/handoff.md" ]]; then
    pass "Approved stop creates .claude/handoff.md"
else
    fail "Approved stop creates .claude/handoff.md" "File not created at $TEST_PROJECT/.claude/handoff.md"
fi

# --- Test 2: Blocked stop does NOT create handoff ---
echo "Test 2: Blocked stop does NOT create handoff"

# Setup fresh project directory
rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Create transcript
TRANSCRIPT_FILE="$TEST_PROJECT/transcript.ndjson"
create_mock_transcript "$TRANSCRIPT_FILE"

# Setup stub that blocks stop (continues)
setup_stub_claude "true"

# Run hook
HOOK_INPUT='{"session_id":"test-handoff-002","transcript_path":"'"$TRANSCRIPT_FILE"'","stop_hook_active":false}'
echo "$HOOK_INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1 || true

if [[ ! -f "$TEST_PROJECT/.claude/handoff.md" ]]; then
    pass "Blocked stop does NOT create handoff"
else
    fail "Blocked stop does NOT create handoff" "File was created when it should not have been"
fi

# --- Test 3: Handoff contains required sections ---
echo "Test 3: Handoff contains required sections"

# Setup fresh project directory
rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Create transcript
TRANSCRIPT_FILE="$TEST_PROJECT/transcript.ndjson"
create_mock_transcript "$TRANSCRIPT_FILE"

# Setup stub that approves stop
setup_stub_claude "false"

# Run hook
HOOK_INPUT='{"session_id":"test-handoff-003","transcript_path":"'"$TRANSCRIPT_FILE"'","stop_hook_active":false}'
echo "$HOOK_INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1 || true

if [[ -f "$TEST_PROJECT/.claude/handoff.md" ]]; then
    HANDOFF_CONTENT=$(cat "$TEST_PROJECT/.claude/handoff.md")

    if echo "$HANDOFF_CONTENT" | grep -q "Session:" && \
       echo "$HANDOFF_CONTENT" | grep -q "Stopped:" && \
       echo "$HANDOFF_CONTENT" | grep -q "Stop Reason" && \
       echo "$HANDOFF_CONTENT" | grep -q "Recent Context"; then
        pass "Handoff contains required sections"
    else
        fail "Handoff contains required sections" "Missing one or more required sections"
    fi
else
    fail "Handoff contains required sections" "Handoff file not created"
fi

# --- Test 4: Handoff includes session ID ---
echo "Test 4: Handoff includes correct session ID"

if [[ -f "$TEST_PROJECT/.claude/handoff.md" ]]; then
    if grep -q "test-handoff-003" "$TEST_PROJECT/.claude/handoff.md"; then
        pass "Handoff includes correct session ID"
    else
        fail "Handoff includes correct session ID" "Session ID not found in handoff"
    fi
else
    skip "Handoff includes correct session ID (no handoff file)"
fi

# --- Test 5: Judge mode skips handoff creation ---
echo "Test 5: Judge mode skips handoff creation"

# Setup fresh project directory
rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Source config and handoff directly for unit test
source "$REPO_ROOT/hooks/lib/config.sh"
source "$REPO_ROOT/hooks/lib/handoff.sh"
load_defaults

# Call handoff with judge mode enabled
export CLAUDE_HOOK_JUDGE_MODE=true
handoff_write_if_needed "approve" "test-session" "Test reason" '[{"role":"user","content":"test"}]'
unset CLAUDE_HOOK_JUDGE_MODE

if [[ ! -f "$TEST_PROJECT/.claude/handoff.md" ]]; then
    pass "Judge mode skips handoff creation"
else
    fail "Judge mode skips handoff creation" "Handoff was created in judge mode"
fi

# --- Test 6: Git info included in git repo ---
echo "Test 6: Git info included when in git repo"

# Setup fresh project directory as git repo
rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"
git init --quiet
git config user.email "test@test.com"
git config user.name "Test"

# Create and commit a file, then modify it
echo "initial" > test.txt
git add test.txt
git commit -m "initial" --quiet
echo "modified" > test.txt

# Create transcript
TRANSCRIPT_FILE="$TEST_PROJECT/transcript.ndjson"
create_mock_transcript "$TRANSCRIPT_FILE"

# Setup stub that approves stop
setup_stub_claude "false"

# Run hook
HOOK_INPUT='{"session_id":"test-handoff-git","transcript_path":"'"$TRANSCRIPT_FILE"'","stop_hook_active":false}'
echo "$HOOK_INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1 || true

if [[ -f "$TEST_PROJECT/.claude/handoff.md" ]]; then
    if grep -q "Git Status" "$TEST_PROJECT/.claude/handoff.md" && \
       grep -q "Branch:" "$TEST_PROJECT/.claude/handoff.md"; then
        pass "Git info included when in git repo"
    else
        fail "Git info included when in git repo" "Git section missing or incomplete"
    fi
else
    fail "Git info included when in git repo" "Handoff file not created"
fi

# --- Test 7: Non-git directory has no git section ---
echo "Test 7: Non-git directory has no git section"

# Setup fresh project directory (not a git repo)
rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Create transcript
TRANSCRIPT_FILE="$TEST_PROJECT/transcript.ndjson"
create_mock_transcript "$TRANSCRIPT_FILE"

# Setup stub that approves stop
setup_stub_claude "false"

# Run hook
HOOK_INPUT='{"session_id":"test-handoff-no-git","transcript_path":"'"$TRANSCRIPT_FILE"'","stop_hook_active":false}'
echo "$HOOK_INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1 || true

if [[ -f "$TEST_PROJECT/.claude/handoff.md" ]]; then
    if ! grep -q "Git Status" "$TEST_PROJECT/.claude/handoff.md"; then
        pass "Non-git directory has no git section"
    else
        fail "Non-git directory has no git section" "Git section found in non-git project"
    fi
else
    fail "Non-git directory has no git section" "Handoff file not created"
fi

# --- Test 8: Unit test handoff_write_if_needed with block decision ---
echo "Test 8: handoff_write_if_needed with block decision does nothing"

# Setup fresh project directory
rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# Source handoff directly for unit test
source "$REPO_ROOT/hooks/lib/config.sh"
source "$REPO_ROOT/hooks/lib/handoff.sh"
load_defaults

# Call handoff with block decision
handoff_write_if_needed "block" "test-session" "Test reason" '[{"role":"user","content":"test"}]'

if [[ ! -f "$TEST_PROJECT/.claude/handoff.md" ]]; then
    pass "handoff_write_if_needed with block decision does nothing"
else
    fail "handoff_write_if_needed with block decision does nothing" "Handoff was created for block decision"
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
