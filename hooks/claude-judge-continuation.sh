#!/bin/bash

# Claude Auto-Continue Plugin - Stop Hook Script (Aggressive Version)
# Automatically evaluates whether Claude should continue working instead of stopping prematurely
# Uses another Claude instance to judge whether continuation is appropriate
# DEFAULT STANCE: Continue unless there's a CLEAR reason to stop

# === Source Library Modules ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/emit.sh"
source "$SCRIPT_DIR/lib/throttle.sh"
source "$SCRIPT_DIR/lib/transcript.sh"
source "$SCRIPT_DIR/lib/judge.sh"
source "$SCRIPT_DIR/lib/settings.sh"

# Load default configuration
load_defaults

# Check if we're in a recursive call (judge Claude instance)
if [ "$CLAUDE_HOOK_JUDGE_MODE" = "true" ]; then
    emit_decision "approve" "Running in judge mode, allowing stop"
    exit 0
fi

# Load per-project settings (fail-closed: defaults if missing/invalid)
settings_load

# Early exit: Plugin disabled by per-project settings
if [ "$REDBULL_ENABLED" = "false" ]; then
    emit_decision "approve" "Disabled by per-project settings"
    exit 0
fi

# Apply aggressiveness to context lines
settings_apply_aggressiveness

# Read the hook event data
EVENT=$(cat)

# Validate input is valid JSON
if ! echo "$EVENT" | jq empty 2>/dev/null; then
    emit_decision "approve" "Invalid JSON input: could not parse hook event"
    exit 0
fi

# Extract key information
STOP_HOOK_ACTIVE=$(echo "$EVENT" | jq -r '.stop_hook_active // false')
TRANSCRIPT_PATH=$(echo "$EVENT" | jq -r '.transcript_path // ""')

# Time-based throttling to prevent infinite loops
SESSION_ID=$(echo "$EVENT" | jq -r '.session_id // "unknown"')
THROTTLE_FILE=$(throttle_file_for_session "$SESSION_ID")
CURRENT_TIME=$(date +%s)

# Early exit: Force stop if continuation limit reached in active stop hook cycle
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    throttle_read "$THROTTLE_FILE"
    if throttle_should_force_stop "$MAX_CONTINUATIONS" "$THROTTLE_WINDOW_SECONDS"; then
        emit_decision "approve" "Maximum continuation cycles reached in time window, forcing stop to prevent infinite loops"
        throttle_clear "$THROTTLE_FILE"
        exit 0
    fi
fi

# --- Transcript file validation (fail closed: approve stop on any error) ---
VALIDATION_ERROR=$(validate_transcript_path "$TRANSCRIPT_PATH")
if [ -n "$VALIDATION_ERROR" ]; then
    emit_decision "approve" "$VALIDATION_ERROR"
    exit 0
fi

# --- Extract recent context ---
RECENT_CONTEXT=$(extract_recent_context_json_array "$TRANSCRIPT_PATH" "$TRANSCRIPT_CONTEXT_LINES")

# Validate we got usable context
if [ -z "$RECENT_CONTEXT" ] || [ "$RECENT_CONTEXT" = "[]" ] || [ "$RECENT_CONTEXT" = "null" ]; then
    emit_decision "approve" "No valid transcript entries found"
    exit 0
fi

# --- Call the judge ---
EVALUATION_RESULT=$(judge_should_continue "$RECENT_CONTEXT" "$CLAUDE_MODEL" "$CLAUDE_WORK_DIR")

# Check if judge call succeeded
if [ $? -ne 0 ]; then
    emit_decision "approve" "Claude evaluation command failed, allowing default stop behavior"
    exit 0
fi

# If no structured output, fall back to allowing stop
if [ -z "$EVALUATION_RESULT" ] || [ "$EVALUATION_RESULT" = "null" ]; then
    emit_decision "approve" "Could not parse Claude evaluation result, allowing default stop behavior"
    exit 0
fi

# Parse the evaluation result (should be JSON)
SHOULD_CONTINUE=$(echo "$EVALUATION_RESULT" | jq -r '.should_continue // false')
REASONING=$(echo "$EVALUATION_RESULT" | jq -r '.reasoning // "No reasoning provided"')

# Make the decision based on Claude's evaluation
if [ "$SHOULD_CONTINUE" = "true" ]; then
    # Update throttle tracking
    throttle_read "$THROTTLE_FILE"
    CONTINUE_COUNT=$((CONTINUE_COUNT + 1))
    throttle_write "$THROTTLE_FILE" "$CONTINUE_COUNT" "$CURRENT_TIME"

    # Block the stop - Claude thinks it can continue
    emit_decision "block" "Claude evaluator determined continuation is appropriate: $REASONING"
else
    # Clear throttle file since we're allowing a legitimate stop
    throttle_clear "$THROTTLE_FILE"

    # Allow the stop - Claude thinks stopping is appropriate
    emit_decision "approve" "Claude evaluator determined stopping is appropriate: $REASONING"
fi

exit 0
