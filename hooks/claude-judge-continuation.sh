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
source "$SCRIPT_DIR/lib/settings.sh"
source "$SCRIPT_DIR/lib/ignore.sh"
source "$SCRIPT_DIR/lib/prompt.sh"
source "$SCRIPT_DIR/lib/handoff.sh"

# Load default configuration
load_defaults

# Emit a decision made before the judge runs (ignore patterns, permission
# language, heuristic signals).
#
# Prefilters bypass the judge, so they also have to honor the two contracts the
# judge path owns:
#   1. Dry-run never blocks a stop, it only reports what it would have done.
#   2. An approved stop that has transcript context writes a handoff snapshot.
#
# Args: decision reason
emit_prefilter_decision() {
    local decision="$1"
    local reason="$2"

    if [ "$decision" = "block" ] && [ "$REDBULL_DRY_RUN" = "true" ]; then
        debug_log "dry_run_mode" --argjson would_continue true
        emit_decision "approve" "[DRY-RUN] Would have blocked (continue): $reason"
        return 0
    fi

    emit_decision "$decision" "$reason"

    if [ "$decision" = "approve" ]; then
        # Handoff runs post-emit to avoid blocking stdout
        handoff_write_if_needed "approve" "$SESSION_ID" "$reason" "$RECENT_CONTEXT"
    fi
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
    VALIDATION_ERROR=$(validate_transcript_path "$TRANSCRIPT_PATH")
    if [ -n "$VALIDATION_ERROR" ]; then
        echo '{"error": "valid transcript_path required for snapshot extraction"}' >&2
        exit 1
    fi

    # Load per-project settings so snapshots reflect real judge inputs
    settings_load
    settings_apply_aggressiveness

    # Build context using lib function
    RECENT_CONTEXT=$(extract_recent_context_json_array "$TRANSCRIPT_PATH" "$TRANSCRIPT_CONTEXT_LINES")

    # Build evaluation prompt using rules-enhanced prompt when available
    if type build_evaluation_prompt_with_rules &>/dev/null; then
        EVALUATION_PROMPT=$(build_evaluation_prompt_with_rules "$RECENT_CONTEXT")
    else
        EVALUATION_PROMPT=$(build_evaluation_prompt "$RECENT_CONTEXT")
    fi

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
    debug_log "invalid_input"
    emit_decision "approve" "Invalid JSON input: could not parse hook event"
    exit 0
fi

# Extract key information
STOP_HOOK_ACTIVE=$(echo "$EVENT" | jq -r '.stop_hook_active // false')
TRANSCRIPT_PATH=$(echo "$EVENT" | jq -r '.transcript_path // ""')

# Time-based throttling to prevent infinite loops
SESSION_ID=$(echo "$EVENT" | jq -r '.session_id // "unknown"')
PERSIST_SESSION_ID="$SESSION_ID"  # Set global for decision persistence (FTR-005)
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

# --- Check ignore patterns (bypass judge if matched) ---
IGNORE_MATCH=$(ignore_should_approve_stop "$RECENT_CONTEXT" 2>/dev/null) || true
if [ -n "$IGNORE_MATCH" ]; then
    debug_log "ignore_pattern_matched" --arg pattern "$IGNORE_MATCH"
    throttle_clear "$THROTTLE_FILE"
    emit_prefilter_decision "approve" "Matched ignore pattern: $IGNORE_MATCH"
    exit 0
fi

# --- Check permission language (Phase 1 prefilter, bypasses judge) ---
PERMISSION_PATTERN=$(detect_permission_language "$RECENT_CONTEXT" 2>/dev/null) || true

if [ -n "$PERMISSION_PATTERN" ]; then
    PERMISSION_DECISION=$(permission_language_decision "$PERMISSION_PATTERN")

    if [ -n "$PERMISSION_DECISION" ]; then
        debug_log "prefilter_path" --arg path "permission"
        debug_log "permission_language" \
            --arg pattern "$PERMISSION_PATTERN" \
            --arg decision "$PERMISSION_DECISION"

        if [ "$PERMISSION_DECISION" = "block" ]; then
            # Update throttle tracking (same as judge continue). Dry-run never
            # blocks, so it must not consume a continuation either.
            if [ "$REDBULL_DRY_RUN" != "true" ]; then
                throttle_read "$THROTTLE_FILE"
                CONTINUE_COUNT=$((CONTINUE_COUNT + 1))
                CURRENT_CONTEXT_HASH=$(compute_context_hash "$RECENT_CONTEXT" 2>/dev/null) || true
                throttle_write "$THROTTLE_FILE" "$CONTINUE_COUNT" "$CURRENT_TIME" "$CURRENT_CONTEXT_HASH"
            fi

            emit_prefilter_decision "block" "Permission-seeking language detected ($PERMISSION_PATTERN): assistant asking to continue work"
            exit 0
        elif [ "$PERMISSION_DECISION" = "approve" ]; then
            throttle_clear "$THROTTLE_FILE"
            emit_prefilter_decision "approve" "User choice needed ($PERMISSION_PATTERN): assistant offering optional work or asking for decision"
            exit 0
        fi
    fi
fi

# --- Check heuristic signals (Phase 3 prefilter, bypasses judge) ---
HEURISTIC_SIGNAL=$(detect_heuristic_signal "$RECENT_CONTEXT" 2>/dev/null) || true

if [ -n "$HEURISTIC_SIGNAL" ]; then
    HEURISTIC_STOP=$(heuristic_should_stop "$HEURISTIC_SIGNAL")

    if [ -n "$HEURISTIC_STOP" ]; then
        # Map to decision for logging
        if [ "$HEURISTIC_STOP" = "true" ]; then
            HEURISTIC_DECISION="approve"
        else
            HEURISTIC_DECISION="block"
        fi

        debug_log "prefilter_path" --arg path "heuristic"
        debug_log "heuristic_signal" \
            --arg signal "$HEURISTIC_SIGNAL" \
            --arg decision "$HEURISTIC_DECISION"

        # Build v2 evaluation payload for consistency with explain.sh
        PERSIST_EVALUATION_RESULT=$(build_heuristic_evaluation "$HEURISTIC_SIGNAL" "$HEURISTIC_STOP" "$HEURISTIC_DECISION")

        if [ "$HEURISTIC_DECISION" = "block" ]; then
            # Update throttle tracking with context hash. Dry-run never blocks,
            # so it must not consume a continuation either.
            if [ "$REDBULL_DRY_RUN" != "true" ]; then
                throttle_read "$THROTTLE_FILE"
                CONTINUE_COUNT=$((CONTINUE_COUNT + 1))
                CURRENT_CONTEXT_HASH=$(compute_context_hash "$RECENT_CONTEXT" 2>/dev/null) || true
                throttle_write "$THROTTLE_FILE" "$CONTINUE_COUNT" "$CURRENT_TIME" "$CURRENT_CONTEXT_HASH"
            fi

            emit_prefilter_decision "block" "Heuristic detected '$HEURISTIC_SIGNAL': work continues without judge"
            exit 0
        elif [ "$HEURISTIC_DECISION" = "approve" ]; then
            throttle_clear "$THROTTLE_FILE"
            emit_prefilter_decision "approve" "Heuristic detected '$HEURISTIC_SIGNAL': user input needed, stopping without judge"
            exit 0
        fi
    fi
fi

# --- Stall Detection (Phase 5) ---
# Compute context hash and detect stall signals before judge call
CURRENT_CONTEXT_HASH=$(compute_context_hash "$RECENT_CONTEXT" 2>/dev/null) || true
STALL_SIGNALS=""
STALL_RISK=0
CONTEXT_UNCHANGED=0
CONFIDENCE_DECLINING=0
CATEGORY_REPEAT_COUNT=0
HAS_STALL_SIGNALS=false

# Get throttle state for stall risk calculation
throttle_read "$THROTTLE_FILE"

if [ -n "$CURRENT_CONTEXT_HASH" ]; then
    # Detect stall from decision log
    DECISION_LOG_FILE="${DECISION_DIR:-$HOME/.claude/redbull}/decision_log.jsonl"
    STALL_SIGNALS=$(detect_stall "$CURRENT_CONTEXT_HASH" "$DECISION_LOG_FILE" 2>/dev/null) || true

    if [ -n "$STALL_SIGNALS" ] && [ "$STALL_SIGNALS" != "null" ]; then
        HAS_STALL_SIGNALS=true
        # Parse JSON signal flags
        CONTEXT_UNCHANGED=$(echo "$STALL_SIGNALS" | jq -r '.context_unchanged // 0')
        CONFIDENCE_DECLINING=$(echo "$STALL_SIGNALS" | jq -r '.confidence_declining // 0')
        CATEGORY_REPEAT_COUNT=$(echo "$STALL_SIGNALS" | jq -r '.category_repeat_count // 0')

        debug_log "stall_detected" \
            --argjson signals "$STALL_SIGNALS" \
            --arg context_hash "$CURRENT_CONTEXT_HASH"
    fi

    # Calculate stall risk score
    STALL_RISK=$(calculate_stall_risk "$CONTEXT_UNCHANGED" "$CONFIDENCE_DECLINING" "$CATEGORY_REPEAT_COUNT" "$CONTINUE_COUNT")

    debug_log "stall_risk" \
        --argjson risk "$(json_num "$STALL_RISK" 0)" \
        --argjson context_unchanged "$(json_num "$CONTEXT_UNCHANGED" 0)" \
        --argjson confidence_declining "$(json_num "$CONFIDENCE_DECLINING" 0)" \
        --argjson throttle_count "$(json_num "$CONTINUE_COUNT" 0)"
fi

# Set stall metadata for persistence
if [ "$HAS_STALL_SIGNALS" = "true" ]; then
    PERSIST_STALL_RISK="$STALL_RISK"
    PERSIST_CONTEXT_HASH="$CURRENT_CONTEXT_HASH"
else
    PERSIST_STALL_RISK=""
    PERSIST_CONTEXT_HASH=""
fi

# --- Call the judge ---
debug_log "prefilter_path" --arg path "judge"
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

# Set global for decision persistence (FTR-005)
PERSIST_EVALUATION_RESULT="$EVALUATION_RESULT"

# Parse the evaluation result (should be JSON)
SHOULD_CONTINUE=$(echo "$EVALUATION_RESULT" | jq -r '.should_continue // false')
REASONING=$(echo "$EVALUATION_RESULT" | jq -r '.reasoning // "No reasoning provided"')
CONFIDENCE=$(echo "$EVALUATION_RESULT" | jq -r '.confidence // 0.5')

# Log evaluation result (boolean only, not reasoning content)
HAS_REASONING=$( [ -n "$REASONING" ] && [ "$REASONING" != "No reasoning provided" ] && echo true || echo false )
debug_log "evaluation_parsed" \
    --argjson should_continue "$(json_bool "$SHOULD_CONTINUE" false)" \
    --argjson has_reasoning "$(json_bool "$HAS_REASONING" false)" \
    --argjson dry_run "$(json_bool "$REDBULL_DRY_RUN" false)"

# --- Stall Risk Threshold Adjustments (Phase 5) ---
STALL_OVERRIDE=""
if [ "$SHOULD_CONTINUE" = "true" ] && [ "$STALL_RISK" -gt 0 ]; then
    # HIGH risk (>70): Force stop if confidence < 0.75
    if [ "$STALL_RISK" -gt 70 ]; then
        if command -v bc >/dev/null 2>&1; then
            if [ "$(echo "$CONFIDENCE < 0.75" | bc -l 2>/dev/null)" = "1" ]; then
                SHOULD_CONTINUE="false"
                STALL_OVERRIDE="high_risk_override"
                REASONING="Stall detected (risk=$STALL_RISK): forcing stop due to low confidence ($CONFIDENCE). Original: $REASONING"
                debug_log "stall_override" \
                    --arg type "high_risk" \
                    --argjson stall_risk "$(json_num "$STALL_RISK" 0)" \
                    --arg confidence "$CONFIDENCE"
            fi
        fi
    # MODERATE risk (40-70): Stricter confidence threshold (0.65 instead of default)
    elif [ "$STALL_RISK" -gt 40 ]; then
        if command -v bc >/dev/null 2>&1; then
            if [ "$(echo "$CONFIDENCE < 0.65" | bc -l 2>/dev/null)" = "1" ]; then
                SHOULD_CONTINUE="false"
                STALL_OVERRIDE="moderate_risk_override"
                REASONING="Stall warning (risk=$STALL_RISK): stricter threshold applied, confidence ($CONFIDENCE) below 0.65. Original: $REASONING"
                debug_log "stall_warning" \
                    --arg type "moderate_risk" \
                    --argjson stall_risk "$(json_num "$STALL_RISK" 0)" \
                    --arg confidence "$CONFIDENCE"
            fi
        fi
    fi
fi

# --- Dry-run mode: evaluate but always approve stop ---
if [ "$REDBULL_DRY_RUN" = "true" ]; then
    debug_log "dry_run_mode" --argjson would_continue "$(json_bool "$SHOULD_CONTINUE" false)"
    # Don't update throttle in dry-run mode
    emit_decision "approve" "[DRY-RUN] Would have $([ "$SHOULD_CONTINUE" = "true" ] && echo "blocked (continue)" || echo "approved (stop)"): $REASONING"
    exit 0
fi

# Make the decision based on Claude's evaluation
if [ "$SHOULD_CONTINUE" = "true" ]; then
    # Update throttle tracking with context hash
    throttle_read "$THROTTLE_FILE"
    CONTINUE_COUNT=$((CONTINUE_COUNT + 1))
    throttle_write "$THROTTLE_FILE" "$CONTINUE_COUNT" "$CURRENT_TIME" "$CURRENT_CONTEXT_HASH"

    debug_log "decision" \
        --arg decision "block" \
        --argjson throttle_count "$(json_num "$CONTINUE_COUNT" 0)" \
        --argjson stall_risk "$(json_num "$STALL_RISK" 0)"

    # Block the stop - Claude thinks it can continue
    emit_decision "block" "Claude evaluator determined continuation is appropriate: $REASONING"
    # Handoff runs post-emit to avoid blocking stdout
    handoff_write_if_needed "block" "$SESSION_ID" "Claude evaluator determined continuation is appropriate: $REASONING" "$RECENT_CONTEXT"
else
    # Clear throttle file since we're allowing a legitimate stop
    throttle_clear "$THROTTLE_FILE"

    debug_log "decision" \
        --arg decision "approve" \
        --argjson throttle_count 0

    # Allow the stop - Claude thinks stopping is appropriate
    emit_decision "approve" "Claude evaluator determined stopping is appropriate: $REASONING"
    # Handoff runs post-emit to avoid blocking stdout
    handoff_write_if_needed "approve" "$SESSION_ID" "Claude evaluator determined stopping is appropriate: $REASONING" "$RECENT_CONTEXT"
fi

exit 0
