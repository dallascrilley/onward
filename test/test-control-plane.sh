#!/bin/bash

# Control Plane Test Suite
# Tests env var configuration, dry-run mode, and ignore patterns

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/claude-judge-continuation.sh"
TEMP_DIR="/tmp/test-control-plane-$$"

# Inject stub claude binary for deterministic testing
export PATH="$SCRIPT_DIR/evals/bin:$PATH"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

mkdir -p "$TEMP_DIR"

echo "🎛️ Control Plane Tests"
echo "======================"
echo ""

# --- Test 1: Config defaults ---
echo "📋 Test: Config defaults load correctly"

# Source config and check defaults
(
    # Unset any inherited env vars to test true defaults
    unset REDBULL_THROTTLE_LIMIT
    unset REDBULL_THROTTLE_WINDOW_SECONDS
    unset REDBULL_TRANSCRIPT_CONTEXT_LINES
    unset REDBULL_JUDGE_MODEL
    unset REDBULL_DRY_RUN
    unset REDBULL_STATE_DIR
    unset REDBULL_LOG_MAX_LINES
    unset REDBULL_LOG_DECISIONS

    source "$SCRIPT_DIR/../hooks/lib/config.sh"
    load_defaults
    [ "$MAX_CONTINUATIONS" = "3" ] || exit 1
    [ "$THROTTLE_WINDOW_SECONDS" = "300" ] || exit 1
    [ "$TRANSCRIPT_CONTEXT_LINES" = "10" ] || exit 1
    [ "$CLAUDE_MODEL" = "haiku" ] || exit 1
    [ "$REDBULL_DRY_RUN" = "false" ] || exit 1
) && pass "Defaults loaded correctly" || fail "Defaults not loaded correctly"

# --- Test 2: Env var overrides ---
echo "📋 Test: Env var overrides work"

(
    export REDBULL_THROTTLE_LIMIT=5
    export REDBULL_THROTTLE_WINDOW_SECONDS=600
    export REDBULL_TRANSCRIPT_CONTEXT_LINES=20
    export REDBULL_JUDGE_MODEL=sonnet
    export REDBULL_DRY_RUN=true

    source "$SCRIPT_DIR/../hooks/lib/config.sh"
    load_defaults

    [ "$MAX_CONTINUATIONS" = "5" ] || exit 1
    [ "$THROTTLE_WINDOW_SECONDS" = "600" ] || exit 1
    [ "$TRANSCRIPT_CONTEXT_LINES" = "20" ] || exit 1
    [ "$CLAUDE_MODEL" = "sonnet" ] || exit 1
    [ "$REDBULL_DRY_RUN" = "true" ] || exit 1
) && pass "Env var overrides work" || fail "Env var overrides failed"

# --- Test 3: Invalid numeric values fallback to defaults ---
echo "📋 Test: Invalid numeric values use defaults"

(
    export REDBULL_THROTTLE_LIMIT="invalid"
    export REDBULL_THROTTLE_WINDOW_SECONDS=-1
    export REDBULL_TRANSCRIPT_CONTEXT_LINES=0

    source "$SCRIPT_DIR/../hooks/lib/config.sh"
    load_defaults

    [ "$MAX_CONTINUATIONS" = "3" ] || exit 1
    [ "$THROTTLE_WINDOW_SECONDS" = "300" ] || exit 1
    [ "$TRANSCRIPT_CONTEXT_LINES" = "10" ] || exit 1
) && pass "Invalid values use defaults" || fail "Invalid values didn't use defaults"

# --- Test 4: Invalid model falls back to haiku ---
echo "📋 Test: Invalid model uses default haiku"

(
    export REDBULL_JUDGE_MODEL="gpt-4"

    source "$SCRIPT_DIR/../hooks/lib/config.sh"
    load_defaults

    [ "$CLAUDE_MODEL" = "haiku" ] || exit 1
) && pass "Invalid model uses haiku" || fail "Invalid model didn't use haiku"

# --- Test 5: Dry-run mode always approves ---
echo "📋 Test: Dry-run mode always approves stop"

# Create test transcript
cat > "$TEMP_DIR/transcript.ndjson" <<'EOF'
{"role":"user","content":"Create a new feature"}
{"role":"assistant","content":"I'll create that feature. First, let me set up the structure. Next I need to implement the core logic."}
EOF

# Create hook event
HOOK_EVENT=$(jq -n \
    --arg path "$TEMP_DIR/transcript.ndjson" \
    '{
        "session_id": "test-dry-run",
        "transcript_path": $path,
        "stop_hook_active": false
    }')

# Run with dry-run mode (should approve even though stub would continue)
RESULT=$(echo "$HOOK_EVENT" | REDBULL_DRY_RUN=true STUB_EXPECTED_DECISION=true "$HOOK_SCRIPT" 2>/dev/null)
DECISION=$(echo "$RESULT" | jq -r '.decision')
REASON=$(echo "$RESULT" | jq -r '.reason')

if [ "$DECISION" = "approve" ] && echo "$REASON" | grep -q "DRY-RUN"; then
    pass "Dry-run mode approves with marker"
else
    fail "Dry-run mode failed: decision=$DECISION, reason=$REASON"
fi

# --- Test 6: Ignore patterns bypass ---
echo "📋 Test: Ignore patterns bypass judge"

# Create ignore patterns file
mkdir -p "$TEMP_DIR/.redbull"
cat > "$TEMP_DIR/.redbull/ignore.txt" <<'EOF'
# Comment line - should be ignored
I have finished
task is complete
EOF

# Create transcript matching an ignore pattern
cat > "$TEMP_DIR/ignore-transcript.ndjson" <<'EOF'
{"role":"user","content":"Deploy the app"}
{"role":"assistant","content":"I have finished deploying the application. Everything is working."}
EOF

HOOK_EVENT=$(jq -n \
    --arg path "$TEMP_DIR/ignore-transcript.ndjson" \
    '{
        "session_id": "test-ignore",
        "transcript_path": $path,
        "stop_hook_active": false
    }')

# Run from temp dir so .redbull/ignore.txt is found
RESULT=$(cd "$TEMP_DIR" && echo "$HOOK_EVENT" | "$HOOK_SCRIPT" 2>/dev/null)
DECISION=$(echo "$RESULT" | jq -r '.decision')
REASON=$(echo "$RESULT" | jq -r '.reason')

if [ "$DECISION" = "approve" ] && echo "$REASON" | grep -q "ignore pattern"; then
    pass "Ignore pattern bypassed judge"
else
    fail "Ignore pattern failed: decision=$DECISION, reason=$REASON"
fi

# --- Test 7: No ignore match proceeds to judge ---
echo "📋 Test: Non-matching transcript proceeds to judge"

# Create transcript that doesn't match any ignore pattern
cat > "$TEMP_DIR/no-ignore-transcript.ndjson" <<'EOF'
{"role":"user","content":"Create a feature"}
{"role":"assistant","content":"I'll create that feature now. Next I need to add tests."}
EOF

HOOK_EVENT=$(jq -n \
    --arg path "$TEMP_DIR/no-ignore-transcript.ndjson" \
    '{
        "session_id": "test-no-ignore",
        "transcript_path": $path,
        "stop_hook_active": false
    }')

# Run from temp dir - should proceed to judge (stub will return continue)
RESULT=$(cd "$TEMP_DIR" && echo "$HOOK_EVENT" | STUB_EXPECTED_DECISION=true "$HOOK_SCRIPT" 2>/dev/null)
DECISION=$(echo "$RESULT" | jq -r '.decision')
REASON=$(echo "$RESULT" | jq -r '.reason')

# Should block (continue) because stub says continue and no ignore match
if [ "$DECISION" = "block" ]; then
    pass "Non-matching transcript proceeded to judge"
else
    fail "Non-matching transcript failed: decision=$DECISION (expected block)"
fi

# --- Test 8: Throttle limit env override ---
echo "📋 Test: Throttle limit override triggers force stop"

# Get the correct throttle file path using the lib function
SESSION_ID="test-throttle-limit"
(
    source "$SCRIPT_DIR/../hooks/lib/throttle.sh"
    throttle_file_for_session "$SESSION_ID"
) > "$TEMP_DIR/throttle-path.txt"
THROTTLE_FILE=$(cat "$TEMP_DIR/throttle-path.txt")

# Create throttle file at limit (count=1, current timestamp)
echo "1:$(date +%s)" > "$THROTTLE_FILE"

cat > "$TEMP_DIR/throttle-transcript.ndjson" <<'EOF'
{"role":"user","content":"Keep going"}
{"role":"assistant","content":"Continuing work. Next I need to do more."}
EOF

HOOK_EVENT=$(jq -n \
    --arg path "$TEMP_DIR/throttle-transcript.ndjson" \
    --arg session "$SESSION_ID" \
    '{
        "session_id": $session,
        "transcript_path": $path,
        "stop_hook_active": true
    }')

# Run with throttle limit of 1 - should force stop (count 1 >= limit 1)
RESULT=$(echo "$HOOK_EVENT" | REDBULL_THROTTLE_LIMIT=1 STUB_EXPECTED_DECISION=true "$HOOK_SCRIPT" 2>/dev/null)
DECISION=$(echo "$RESULT" | jq -r '.decision')

rm -f "$THROTTLE_FILE"

if [ "$DECISION" = "approve" ]; then
    pass "Throttle limit override triggers force stop"
else
    fail "Throttle limit override failed: decision=$DECISION (expected approve)"
fi

echo ""
echo "======================"
echo -e "${GREEN}All control plane tests passed!${NC}"
