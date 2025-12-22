#!/bin/bash

# Claude Auto-Continue Plugin - Stop Hook Script (Aggressive Version)
# Automatically evaluates whether Claude should continue working instead of stopping prematurely
# Uses another Claude instance to judge whether continuation is appropriate
# DEFAULT STANCE: Continue unless there's a CLEAR reason to stop

# === Source Library Modules ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/debug.sh"
source "$SCRIPT_DIR/lib/emit.sh"
source "$SCRIPT_DIR/lib/throttle.sh"
source "$SCRIPT_DIR/lib/transcript.sh"
source "$SCRIPT_DIR/lib/judge.sh"

# Load default configuration
load_defaults

# Check if we're in a recursive call (judge Claude instance)
if [ "$CLAUDE_HOOK_JUDGE_MODE" = "true" ]; then
    debug_log "recursion_guard"
    emit_decision "approve" "Running in judge mode, allowing stop"
    exit 0
fi

# === Snapshot Extraction Mode ===
# When SNAPSHOT_EXTRACT_MODE=true, output prompt/schema components for testing
# Pseudocode:
# - If snapshot mode is enabled AND explicitly allowed, emit prompt/schema and exit
# - If snapshot mode is enabled without explicit allow, warn and continue normal flow
if [ "$SNAPSHOT_EXTRACT_MODE" = "true" ] && [ "$SNAPSHOT_EXTRACT_ALLOW" = "true" ]; then
    # Read hook event from stdin
    EVENT=$(cat)
    TRANSCRIPT_PATH=$(echo "$EVENT" | jq -r '.transcript_path // ""')

    # Validate transcript file
    VALIDATION_ERROR=$(validate_transcript_path "$TRANSCRIPT_PATH")
    if [ -n "$VALIDATION_ERROR" ]; then
        echo '{"error": "valid transcript_path required for snapshot extraction"}' >&2
        exit 1
    fi

    # Build context using lib function
    RECENT_CONTEXT=$(extract_recent_context_json_array "$TRANSCRIPT_PATH" "$TRANSCRIPT_CONTEXT_LINES")

    # Build evaluation prompt using lib function
    EVALUATION_PROMPT=$(build_evaluation_prompt "$RECENT_CONTEXT")

    # Output as JSON for snapshot comparison
    jq -n \
        --arg schema "$JUDGE_JSON_SCHEMA" \
        --arg system "$JUDGE_SYSTEM_PROMPT" \
        --arg eval "$EVALUATION_PROMPT" \
        '{"json_schema": $schema, "system_prompt": $system, "evaluation_prompt": $eval}'
    exit 0
elif [ "$SNAPSHOT_EXTRACT_MODE" = "true" ]; then
    echo "SNAPSHOT_EXTRACT_MODE ignored unless SNAPSHOT_EXTRACT_ALLOW=true" >&2
fi

# Read the hook event data
EVENT=$(cat)

# Validate input is valid JSON
if ! echo "$EVENT" | jq empty 2>/dev/null; then
    debug_log "invalid_input"
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

# Log parsed event metadata (basename only for security)
debug_log "event_parsed" \
    --argjson stop_hook_active "$(json_bool "$STOP_HOOK_ACTIVE" false)" \
    --arg transcript_file "$(basename "$TRANSCRIPT_PATH" 2>/dev/null || echo 'none')"

# Early exit: Force stop if continuation limit reached in active stop hook cycle
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    throttle_read "$THROTTLE_FILE"
    debug_log "throttle_state" \
        --argjson continue_count "$(json_num "$CONTINUE_COUNT" 0)" \
        --argjson last_continue_time "$(json_num "$LAST_CONTINUE_TIME" 0)" \
        --argjson current_time "$(json_num "$CURRENT_TIME" 0)"
    if throttle_should_force_stop "$MAX_CONTINUATIONS" "$THROTTLE_WINDOW_SECONDS"; then
        debug_log "throttle_force_stop" \
            --argjson continue_count "$(json_num "$CONTINUE_COUNT" 0)" \
            --argjson max_continuations "$(json_num "$MAX_CONTINUATIONS" 3)"
        emit_decision "approve" "Maximum continuation cycles reached in time window, forcing stop to prevent infinite loops"
        throttle_clear "$THROTTLE_FILE"
        exit 0
    fi
fi

# --- Transcript file validation (fail closed: approve stop on any error) ---
VALIDATION_ERROR=$(validate_transcript_path "$TRANSCRIPT_PATH")
if [ -n "$VALIDATION_ERROR" ]; then
    debug_log "transcript_error" --arg reason "$VALIDATION_ERROR"
    emit_decision "approve" "$VALIDATION_ERROR"
    exit 0
fi

# --- Extract recent context ---
RECENT_CONTEXT=$(extract_recent_context_json_array "$TRANSCRIPT_PATH" "$TRANSCRIPT_CONTEXT_LINES")

# Validate we got usable context
CONTEXT_ENTRY_COUNT=$(echo "$RECENT_CONTEXT" | jq 'length // 0' 2>/dev/null || echo 0)
debug_log "context_extracted" --argjson entry_count "$(json_num "$CONTEXT_ENTRY_COUNT" 0)"

if [ -z "$RECENT_CONTEXT" ] || [ "$RECENT_CONTEXT" = "[]" ] || [ "$RECENT_CONTEXT" = "null" ]; then
    debug_log "transcript_error" --arg reason "no_valid_entries"
    emit_decision "approve" "No valid transcript entries found"
    exit 0
fi

# --- Call the judge ---
debug_log "claude_invoking" --arg model "$CLAUDE_MODEL"
EVALUATION_RESULT=$(judge_should_continue "$RECENT_CONTEXT" "$CLAUDE_MODEL" "$CLAUDE_WORK_DIR")
CLAUDE_EXIT_CODE=$?

debug_log "claude_invoked" \
    --arg model "$CLAUDE_MODEL" \
    --argjson exit_code "$(json_num "$CLAUDE_EXIT_CODE" 0)"

# Check if judge call succeeded
if [ $CLAUDE_EXIT_CODE -ne 0 ]; then
    debug_log "claude_error" --arg reason "command_failed"
    emit_decision "approve" "Claude evaluation command failed, allowing default stop behavior"
    exit 0
fi

# If no structured output, fall back to allowing stop
if [ -z "$EVALUATION_RESULT" ] || [ "$EVALUATION_RESULT" = "null" ]; then
    debug_log "claude_error" --arg reason "parse_failed"
    emit_decision "approve" "Could not parse Claude evaluation result, allowing default stop behavior"
    exit 0
fi

# Parse the evaluation result (should be JSON)
SHOULD_CONTINUE=$(echo "$EVALUATION_RESULT" | jq -r '.should_continue // false')
REASONING=$(echo "$EVALUATION_RESULT" | jq -r '.reasoning // "No reasoning provided"')

# Log evaluation result (boolean only, not reasoning content)
HAS_REASONING=$( [ -n "$REASONING" ] && [ "$REASONING" != "No reasoning provided" ] && echo true || echo false )
debug_log "evaluation_parsed" \
    --argjson should_continue "$(json_bool "$SHOULD_CONTINUE" false)" \
    --argjson has_reasoning "$(json_bool "$HAS_REASONING" false)"

# Make the decision based on Claude's evaluation
if [ "$SHOULD_CONTINUE" = "true" ]; then
    # Update throttle tracking
    throttle_read "$THROTTLE_FILE"
    CONTINUE_COUNT=$((CONTINUE_COUNT + 1))
    throttle_write "$THROTTLE_FILE" "$CONTINUE_COUNT" "$CURRENT_TIME"

    debug_log "decision" \
        --arg decision "block" \
        --argjson throttle_count "$(json_num "$CONTINUE_COUNT" 0)"

    # Block the stop - Claude thinks it can continue
    emit_decision "block" "Claude evaluator determined continuation is appropriate: $REASONING"
else
    # Clear throttle file since we're allowing a legitimate stop
    throttle_clear "$THROTTLE_FILE"

    debug_log "decision" \
        --arg decision "approve" \
        --argjson throttle_count 0

    # Allow the stop - Claude thinks stopping is appropriate
    emit_decision "approve" "Claude evaluator determined stopping is appropriate: $REASONING"
fi

exit 0
