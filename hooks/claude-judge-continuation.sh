#!/bin/bash

# Claude Auto-Continue Plugin - Stop Hook Script (Aggressive Version)
# Automatically evaluates whether Claude should continue working instead of stopping prematurely
# Uses another Claude instance to judge whether continuation is appropriate
# DEFAULT STANCE: Continue unless there's a CLEAR reason to stop

# Configuration constants
MAX_CONTINUATIONS=3
THROTTLE_WINDOW_SECONDS=300
TRANSCRIPT_CONTEXT_LINES=10
CLAUDE_MODEL="haiku"
CLAUDE_WORK_DIR="$HOME/.claude/double-shot-latte"

# === Prompt/Schema Definitions (used by both production and snapshot extraction) ===
JSON_SCHEMA='{"type":"object","properties":{"should_continue":{"type":"boolean"},"reasoning":{"type":"string"}},"required":["should_continue","reasoning"]}'

SYSTEM_PROMPT="You are a conversation state classifier. Your only job is to analyze conversation transcripts and determine if the assistant has more autonomous work to do. You output structured JSON. You do not write code or use tools."

# Build evaluation prompt with conversation context
# Usage: EVALUATION_PROMPT=$(build_evaluation_prompt "$RECENT_CONTEXT")
build_evaluation_prompt() {
    local context="$1"
    cat <<EOF
Analyze this conversation and determine: Does the assistant have more autonomous work to do RIGHT NOW?

Conversation:
$context

CONTINUE (should_continue: true) ONLY IF the assistant explicitly states what it will do next:
- Phrases indicating intent to continue (e.g., 'Next I need to...', 'Now I'll...', 'Moving on to...')
- Incomplete todo list with remaining items marked pending
- Stated follow-up tasks not yet performed

STOP (should_continue: false) in ALL other cases:

1. TASK COMPLETION - The assistant indicates work is finished:
   - Completion statements (done, complete, finished, ready, all set)
   - Summary of accomplished work with no stated next steps
   - Confirming something is working/verified/installed

2. QUESTIONS - The assistant needs user input:
   - Asking for approval, decisions, clarification, or confirmation
   - Offering optional actions (e.g., 'Want me to...?', 'Should I also...?')
   - Note: Mid-task continuation questions (e.g., 'Should I continue?' when work is ongoing) = CONTINUE

3. BLOCKERS - The assistant cannot proceed:
   - Unresolved errors or missing information
   - Uncertainty about requirements

KEY: If the assistant is WAITING for the user (whether after completing work OR asking a question), that means STOP. Waiting ≠ more autonomous work to do.

Default to STOP when uncertain.
EOF
}

# Build recent transcript context as a JSON array.
# Steps:
# - Read the last 50 lines
# - Drop empty lines and invalid JSON
# - Keep the most recent TRANSCRIPT_CONTEXT_LINES
# - Pack into a JSON array
build_recent_context() {
    local transcript_path="$1"
    tail -n 50 "$transcript_path" 2>/dev/null | \
        grep -v '^[[:space:]]*$' | \
        while IFS= read -r line; do
            printf '%s\n' "$line" | jq -e '.' >/dev/null 2>&1 && printf '%s\n' "$line"
        done | \
        tail -n "$TRANSCRIPT_CONTEXT_LINES" | \
        jq -s '.' 2>/dev/null
}

# Debug configuration (disabled by default)
REDBULL_DEBUG="${REDBULL_DEBUG:-false}"

# Verify jq is available for debug logging; silently disable if not
if [ "$REDBULL_DEBUG" = "true" ] && ! command -v jq >/dev/null 2>&1; then
    REDBULL_DEBUG="false"
fi

# Debug log emitter - writes compact structured JSON to stderr only
# Logs metadata only, never transcript content or secrets
debug_log() {
    [ "$REDBULL_DEBUG" = "true" ] || return 0
    local event="$1"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    shift
    jq -cn --arg ts "$ts" --arg event "$event" \
        '$ARGS.named + {timestamp: $ts, event: $event}' "$@" >&2
}

# Safely format a value for jq --argjson (numbers)
# Usage: json_num <value> [default]
json_num() {
    local val="$1"
    local default="${2:-0}"
    [[ "$val" =~ ^-?[0-9]+$ ]] && echo "$val" || echo "$default"
}

# Safely format a boolean for jq --argjson
# Usage: json_bool <value> [default]
json_bool() {
    local val="$1"
    local default="${2:-false}"
    case "$val" in
        true|TRUE|True|1) echo "true" ;;
        false|FALSE|False|0) echo "false" ;;
        *) echo "$default" ;;
    esac
}

# Single output emitter - all stdout JSON goes through here
emit_decision() {
    local decision="$1"
    local reason="$2"
    jq -n --arg d "$decision" --arg r "$reason" '{"decision": $d, "reason": $r}'
}

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
    if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] || [ ! -r "$TRANSCRIPT_PATH" ]; then
        echo '{"error": "valid transcript_path required for snapshot extraction"}' >&2
        exit 1
    fi

    # Build context using same logic as production
    RECENT_CONTEXT=$(build_recent_context "$TRANSCRIPT_PATH")

    # Build evaluation prompt
    EVALUATION_PROMPT=$(build_evaluation_prompt "$RECENT_CONTEXT")

    # Output as JSON for snapshot comparison
    jq -n \
        --arg schema "$JSON_SCHEMA" \
        --arg system "$SYSTEM_PROMPT" \
        --arg eval "$EVALUATION_PROMPT" \
        '{"json_schema": $schema, "system_prompt": $system, "evaluation_prompt": $eval}'
    exit 0
elif [ "$SNAPSHOT_EXTRACT_MODE" = "true" ]; then
    echo "SNAPSHOT_EXTRACT_MODE ignored unless SNAPSHOT_EXTRACT_ALLOW=true" >&2
fi

# === Throttle Helper Functions ===
# Manages continuation throttling to prevent infinite loops
# File format: <count>:<unix_epoch_seconds>
#
# Pseudocode:
# - Derive a safe session key (hash preferred, sanitized fallback).
# - Read throttle state; if missing/malformed/future timestamp, reset + clear.
# - Increment count when a stop is blocked; reset to 0 when outside window.
# - Write throttle state via temp file then atomic rename.
# - Clear throttle state when stopping.

# Returns throttle file path for a session ID
throttle_file_for_session() {
    local session_id="$1"
    local safe_session_id
    local session_hash=""

    # Sanitize non-filesystem-safe characters; hash if available to avoid collisions/length issues.
    safe_session_id="${session_id//[^A-Za-z0-9._-]/_}"
    safe_session_id="${safe_session_id//../_}"
    [ -n "$safe_session_id" ] || safe_session_id="unknown"

    if command -v shasum >/dev/null 2>&1; then
        read -r session_hash _ <<<"$(printf '%s' "$session_id" | shasum -a 256 2>/dev/null)"
    elif command -v sha256sum >/dev/null 2>&1; then
        read -r session_hash _ <<<"$(printf '%s' "$session_id" | sha256sum 2>/dev/null)"
    fi

    if [ -n "$session_hash" ]; then
        safe_session_id="$session_hash"
    else
        safe_session_id="${safe_session_id:0:64}"
    fi

    echo "/tmp/.claude-continue-throttle-${safe_session_id}"
}

# Reads throttle file, sets CONTINUE_COUNT and LAST_CONTINUE_TIME globals
throttle_read() {
    local throttle_file="$1"
    CONTINUE_COUNT=0
    LAST_CONTINUE_TIME=0
    [ -f "$throttle_file" ] || return 0
    local throttle_data
    throttle_data=$(<"$throttle_file")
    [ -n "$throttle_data" ] || return 0
    local count
    local timestamp
    local extra
    IFS=':' read -r count timestamp extra <<<"$throttle_data"
    if [ -z "$count" ] || [ -z "$timestamp" ] || [ -n "$extra" ]; then
        throttle_clear "$throttle_file"
        return 0
    fi
    if ! [[ "$count" =~ ^[0-9]+$ ]] || ! [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        throttle_clear "$throttle_file"
        return 0
    fi
    if [ "$timestamp" -gt "$CURRENT_TIME" ]; then
        throttle_clear "$throttle_file"
        return 0
    fi
    CONTINUE_COUNT="$count"
    LAST_CONTINUE_TIME="$timestamp"
}

# Writes count:timestamp to throttle file
throttle_write() {
    local throttle_file="$1"
    local count="$2"
    local timestamp="$3"
    local temp_file
    temp_file=$(mktemp "${throttle_file}.tmp.XXXXXX") || return 1
    if ! printf '%s:%s\n' "$count" "$timestamp" > "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi
    if ! mv -f "$temp_file" "$throttle_file"; then
        rm -f "$temp_file"
        return 1
    fi
}

# Returns 0 if should force stop, 1 otherwise
# Side effect: Resets CONTINUE_COUNT if outside window
throttle_should_force_stop() {
    local max_continues="${1:-$MAX_CONTINUATIONS}"
    local window_seconds="${2:-$THROTTLE_WINDOW_SECONDS}"
    local time_since_last=$((CURRENT_TIME - LAST_CONTINUE_TIME))
    if [ "$time_since_last" -gt "$window_seconds" ]; then
        CONTINUE_COUNT=0
        return 1
    fi
    [ "$CONTINUE_COUNT" -ge "$max_continues" ]
}

# Removes throttle file
throttle_clear() {
    local throttle_file="$1"
    rm -f "$throttle_file"
}

# === End Throttle Helpers ===

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
if [ -z "$TRANSCRIPT_PATH" ]; then
    debug_log "transcript_error" --arg reason "no_path"
    emit_decision "approve" "No transcript path provided"
    exit 0
fi

if [ ! -f "$TRANSCRIPT_PATH" ]; then
    debug_log "transcript_error" --arg reason "not_found"
    emit_decision "approve" "Transcript file not found"
    exit 0
fi

if [ ! -r "$TRANSCRIPT_PATH" ]; then
    debug_log "transcript_error" --arg reason "not_readable"
    emit_decision "approve" "Transcript file not readable"
    exit 0
fi

if [ ! -s "$TRANSCRIPT_PATH" ]; then
    debug_log "transcript_error" --arg reason "empty"
    emit_decision "approve" "Transcript file is empty"
    exit 0
fi

# --- Extract last TRANSCRIPT_CONTEXT_LINES valid NDJSON entries (tolerant of empty/invalid lines) ---
# Read more lines than needed to ensure we get enough valid ones after filtering
RECENT_CONTEXT=$(build_recent_context "$TRANSCRIPT_PATH")

# Validate we got usable context
CONTEXT_ENTRY_COUNT=$(echo "$RECENT_CONTEXT" | jq 'length // 0' 2>/dev/null || echo 0)
debug_log "context_extracted" --argjson entry_count "$(json_num "$CONTEXT_ENTRY_COUNT" 0)"

if [ -z "$RECENT_CONTEXT" ] || [ "$RECENT_CONTEXT" = "[]" ] || [ "$RECENT_CONTEXT" = "null" ]; then
    debug_log "transcript_error" --arg reason "no_valid_entries"
    emit_decision "approve" "No valid transcript entries found"
    exit 0
fi

# Ensure the working directory exists
mkdir -p "$CLAUDE_WORK_DIR"

# Build evaluation prompt using the shared function
EVALUATION_PROMPT=$(build_evaluation_prompt "$RECENT_CONTEXT")

# Use claude --print to get the evaluation with structured output
# Set environment variable to prevent recursion, use JSON schema, disable tools
# Run claude in the dedicated working directory
CLAUDE_RESPONSE=$(echo "$EVALUATION_PROMPT" | (cd "$CLAUDE_WORK_DIR" && CLAUDE_HOOK_JUDGE_MODE=true claude --print --model "$CLAUDE_MODEL" --output-format json --json-schema "$JSON_SCHEMA" --system-prompt "$SYSTEM_PROMPT" --disallowedTools '*') 2>/dev/null)
CLAUDE_EXIT_CODE=$?

debug_log "claude_invoked" \
    --arg model "$CLAUDE_MODEL" \
    --argjson exit_code "$(json_num "$CLAUDE_EXIT_CODE" 0)"

# Check if claude command succeeded
if [ $CLAUDE_EXIT_CODE -ne 0 ]; then
    debug_log "claude_error" --arg reason "command_failed"
    emit_decision "approve" "Claude evaluation command failed, allowing default stop behavior"
    exit 0
fi

# Extract the structured output from the claude response (stream array or single object)
EVALUATION_RESULT=$(echo "$CLAUDE_RESPONSE" | jq -c 'if type=="array" then .[] else . end | select(has("structured_output")) | .structured_output // empty' 2>/dev/null)

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
