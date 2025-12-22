#!/bin/bash

# Integration tests for FTR-005: Decision persistence and explain command
# Tests that:
# 1. Hook writes last_decision.json after decisions
# 2. explain.sh reads and formats correctly
# 3. Missing file produces helpful message
# 4. Decision log rotation works when enabled

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
EXPLAIN_SCRIPT="$REPO_ROOT/scripts/explain.sh"

# Test isolation: use temp directory for ~/.claude
TEST_HOME=$(mktemp -d)
TEST_DECISION_DIR="$TEST_HOME/.claude/redbull"
ORIGINAL_HOME="$HOME"

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_HOME"
    export HOME="$ORIGINAL_HOME"
}
trap cleanup EXIT

# Switch to test home
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

echo "=========================================="
echo "FTR-005 Integration Tests"
echo "=========================================="
echo ""

# --- Test 1: Hook creates last_decision.json ---
echo "Test 1: Hook writes last_decision.json on decision"

TRANSCRIPT_FILE=$(mktemp)
create_mock_transcript "$TRANSCRIPT_FILE"

# Run hook (uses stub claude via PATH if EVAL_OFFLINE=1, otherwise real claude)
HOOK_INPUT='{"session_id":"test-session-001","transcript_path":"'"$TRANSCRIPT_FILE"'","stop_hook_active":false}'

# For this test, we'll run in offline mode with a stub
mkdir -p "$TEST_HOME/bin" "$TEST_DECISION_DIR"
cat > "$TEST_HOME/bin/claude" << 'STUB'
#!/bin/bash
cat >/dev/null  # consume stdin
echo '[{"type":"result","structured_output":{"should_continue":false,"reasoning":"Test: work appears complete"}}]'
STUB
chmod +x "$TEST_HOME/bin/claude"

# Export PATH so it's inherited by subprocesses
export PATH="$TEST_HOME/bin:$PATH"
echo "$HOOK_INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f "$TEST_DECISION_DIR/last_decision.json" ]]; then
    # Validate JSON structure
    if jq -e '.timestamp and .session_id and .decision and .reason' "$TEST_DECISION_DIR/last_decision.json" > /dev/null 2>&1; then
        pass "Hook creates valid last_decision.json with required fields"
    else
        fail "Hook creates last_decision.json" "Missing required fields"
    fi
else
    fail "Hook creates last_decision.json" "File not created at $TEST_DECISION_DIR/last_decision.json"
fi

rm -f "$TRANSCRIPT_FILE"

# --- Test 2: explain.sh reads and formats decision ---
echo "Test 2: explain.sh reads and formats last decision"

if [[ -f "$TEST_DECISION_DIR/last_decision.json" ]]; then
    OUTPUT=$("$EXPLAIN_SCRIPT" 2>&1)

    # Check for expected output elements
    if echo "$OUTPUT" | grep -q "Last Decision:" && \
       echo "$OUTPUT" | grep -q "Timestamp:" && \
       echo "$OUTPUT" | grep -q "Session:" && \
       echo "$OUTPUT" | grep -q "Reasoning:"; then
        pass "explain.sh formats decision with all required sections"
    else
        fail "explain.sh formats decision" "Missing expected sections in output"
    fi
else
    skip "explain.sh formats decision (no decision file from previous test)"
fi

# --- Test 3: explain.sh --json outputs valid JSON ---
echo "Test 3: explain.sh --json outputs valid JSON"

if [[ -f "$TEST_DECISION_DIR/last_decision.json" ]]; then
    JSON_OUTPUT=$("$EXPLAIN_SCRIPT" --json 2>&1)

    if echo "$JSON_OUTPUT" | jq -e '.' > /dev/null 2>&1; then
        pass "explain.sh --json outputs valid JSON"
    else
        fail "explain.sh --json outputs valid JSON" "Invalid JSON output"
    fi
else
    skip "explain.sh --json test (no decision file)"
fi

# --- Test 4: explain.sh handles missing file gracefully ---
echo "Test 4: explain.sh handles missing decision file"

# Remove decision file
rm -f "$TEST_DECISION_DIR/last_decision.json"

OUTPUT=$("$EXPLAIN_SCRIPT" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]] && echo "$OUTPUT" | grep -qi "no decision"; then
    pass "explain.sh handles missing file gracefully"
else
    fail "explain.sh handles missing file" "Expected helpful message about no decision history"
fi

# --- Test 5: Decision includes evaluation when available ---
echo "Test 5: Decision includes evaluation field when Claude evaluates"

TRANSCRIPT_FILE=$(mktemp)
create_mock_transcript "$TRANSCRIPT_FILE"
HOOK_INPUT='{"session_id":"test-session-002","transcript_path":"'"$TRANSCRIPT_FILE"'","stop_hook_active":false}'

# Run hook again to create fresh decision (PATH already exported)
echo "$HOOK_INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f "$TEST_DECISION_DIR/last_decision.json" ]]; then
    if jq -e '.evaluation' "$TEST_DECISION_DIR/last_decision.json" > /dev/null 2>&1; then
        pass "Decision includes evaluation field"
    else
        fail "Decision includes evaluation field" "evaluation field missing"
    fi
else
    fail "Decision includes evaluation field" "Decision file not created"
fi

rm -f "$TRANSCRIPT_FILE"

# --- Test 6: explain.sh --verbose shows evaluation details ---
echo "Test 6: explain.sh --verbose shows evaluation details"

if [[ -f "$TEST_DECISION_DIR/last_decision.json" ]]; then
    VERBOSE_OUTPUT=$("$EXPLAIN_SCRIPT" --verbose 2>&1)

    if echo "$VERBOSE_OUTPUT" | grep -q "Evaluation Details:" && \
       echo "$VERBOSE_OUTPUT" | grep -q "should_continue:"; then
        pass "explain.sh --verbose shows evaluation details"
    else
        fail "explain.sh --verbose shows evaluation details" "Missing evaluation section"
    fi
else
    skip "explain.sh --verbose test (no decision file)"
fi

# --- Test 7: Decision log rotation ---
echo "Test 7: Decision log rotation (when enabled)"

# Enable logging and set low max
export REDBULL_LOG_DECISIONS=true
export REDBULL_LOG_MAX_LINES=5

TRANSCRIPT_FILE=$(mktemp)
create_mock_transcript "$TRANSCRIPT_FILE"

# Generate more than max decisions (PATH already exported)
for i in {1..8}; do
    HOOK_INPUT='{"session_id":"test-session-log-'"$i"'","transcript_path":"'"$TRANSCRIPT_FILE"'","stop_hook_active":false}'
    echo "$HOOK_INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1
done

LOG_FILE="$TEST_DECISION_DIR/decision_log.jsonl"
if [[ -f "$LOG_FILE" ]]; then
    LINE_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
    if [[ "$LINE_COUNT" -le 5 ]]; then
        pass "Decision log rotation works (log bounded to $LINE_COUNT lines)"
    else
        fail "Decision log rotation" "Log has $LINE_COUNT lines, expected <= 5"
    fi
else
    fail "Decision log rotation" "Log file not created at $LOG_FILE"
fi

rm -f "$TRANSCRIPT_FILE"
unset REDBULL_LOG_DECISIONS
unset REDBULL_LOG_MAX_LINES

# --- Test 8: Early exit decisions still persist ---
echo "Test 8: Early exit decisions (no transcript) persist"

# Trigger early exit by not providing transcript path (PATH already exported)
HOOK_INPUT='{"session_id":"test-early-exit","stop_hook_active":false}'
echo "$HOOK_INPUT" | "$HOOK_SCRIPT" > /dev/null 2>&1

if [[ -f "$TEST_DECISION_DIR/last_decision.json" ]]; then
    SESSION=$(jq -r '.session_id' "$TEST_DECISION_DIR/last_decision.json")
    if [[ "$SESSION" == "test-early-exit" ]]; then
        pass "Early exit decisions persist with session_id"
    else
        fail "Early exit decisions persist" "Wrong session_id: $SESSION"
    fi
else
    fail "Early exit decisions persist" "Decision file not updated"
fi

# --- Test 9: explain.sh respects DECISION_DIR override ---
echo "Test 9: explain.sh respects DECISION_DIR override"

# Pseudocode: write decision in custom dir -> run explain.sh with DECISION_DIR -> expect output to include session id
CUSTOM_DECISION_DIR="$TEST_HOME/.claude/custom-latte"
mkdir -p "$CUSTOM_DECISION_DIR"
cat > "$CUSTOM_DECISION_DIR/last_decision.json" << 'EOF'
{
  "timestamp": "2025-12-22T00:00:00Z",
  "session_id": "custom-001",
  "decision": "approve",
  "reason": "Custom decision dir test"
}
EOF

OUTPUT=$(DECISION_DIR="$CUSTOM_DECISION_DIR" "$EXPLAIN_SCRIPT" 2>&1)
if echo "$OUTPUT" | grep -q "custom-001"; then
    pass "explain.sh respects DECISION_DIR override"
else
    fail "explain.sh respects DECISION_DIR override" "Expected session_id from custom decision dir"
fi

# --- Test 10: Judge mode does not overwrite last decision ---
echo "Test 10: Judge mode does not overwrite last decision"

# Pseudocode: write sentinel decision -> run hook in judge mode -> ensure file unchanged
cat > "$TEST_DECISION_DIR/last_decision.json" << 'EOF'
{
  "timestamp": "2025-12-22T01:00:00Z",
  "session_id": "sentinel-001",
  "decision": "approve",
  "reason": "Sentinel decision"
}
EOF

SENTINEL_CONTENT=$(cat "$TEST_DECISION_DIR/last_decision.json")
CLAUDE_HOOK_JUDGE_MODE=true "$HOOK_SCRIPT" < /dev/null > /dev/null 2>&1
UPDATED_CONTENT=$(cat "$TEST_DECISION_DIR/last_decision.json")

if [[ "$UPDATED_CONTENT" == "$SENTINEL_CONTENT" ]]; then
    pass "Judge mode does not overwrite last_decision.json"
else
    fail "Judge mode does not overwrite last_decision.json" "Decision file was modified during judge mode"
fi

# --- Test 11: Invalid evaluation JSON does not corrupt decision file ---
echo "Test 11: Invalid evaluation JSON does not corrupt decision file"

# Pseudocode: call emit_decision with invalid evaluation JSON -> expect valid last_decision.json
INVALID_DECISION_DIR="$TEST_HOME/.claude/invalid-eval"
mkdir -p "$INVALID_DECISION_DIR"

set +e
(
    set +e
    source "$REPO_ROOT/hooks/lib/config.sh"
    source "$REPO_ROOT/hooks/lib/emit.sh"
    load_defaults
    DECISION_DIR="$INVALID_DECISION_DIR"
    LAST_DECISION_FILE="$DECISION_DIR/last_decision.json"
    PERSIST_SESSION_ID="test-invalid-json"
    PERSIST_EVALUATION_RESULT='{"bad":'
    emit_decision "approve" "Invalid evaluation test" > /dev/null 2>&1
)
EMIT_STATUS=$?
set -e

if [[ $EMIT_STATUS -ne 0 ]]; then
    fail "Invalid evaluation JSON handling" "emit_decision exited with $EMIT_STATUS"
elif [[ ! -f "$INVALID_DECISION_DIR/last_decision.json" ]]; then
    fail "Invalid evaluation JSON handling" "Decision file not created"
elif jq -e '.timestamp and .session_id and .decision and .reason' "$INVALID_DECISION_DIR/last_decision.json" > /dev/null 2>&1; then
    pass "Invalid evaluation JSON does not corrupt decision file"
else
    fail "Invalid evaluation JSON handling" "Decision file contains invalid JSON"
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
