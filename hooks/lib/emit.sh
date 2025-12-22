#!/bin/bash
# emit.sh - Single point of stdout JSON output for hooks
#
# All hook decisions must go through this emitter to ensure:
# - Consistent JSON format
# - Only stdout contains JSON (no debug output)
# - Easy to test and mock
# - Decision persistence for debugging (FTR-005)

# Persists the decision to last_decision.json and optionally to decision_log.jsonl
persist_decision() {
    local decision="$1"
    local reason="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Ensure decision directory exists
    mkdir -p "$DECISION_DIR" 2>/dev/null || return 0

    # Build the decision record with available context
    local decision_json
    if [ -n "$PERSIST_EVALUATION_RESULT" ] && [ "$PERSIST_EVALUATION_RESULT" != "null" ]; then
        decision_json=$(jq -n \
            --arg ts "$timestamp" \
            --arg sid "$PERSIST_SESSION_ID" \
            --arg dec "$decision" \
            --arg reason "$reason" \
            --argjson eval "$PERSIST_EVALUATION_RESULT" \
            '{
                timestamp: $ts,
                session_id: $sid,
                decision: $dec,
                reason: $reason,
                evaluation: $eval
            }')
    else
        decision_json=$(jq -n \
            --arg ts "$timestamp" \
            --arg sid "$PERSIST_SESSION_ID" \
            --arg dec "$decision" \
            --arg reason "$reason" \
            '{
                timestamp: $ts,
                session_id: $sid,
                decision: $dec,
                reason: $reason
            }')
    fi

    # Write last decision atomically
    local temp_file
    temp_file=$(mktemp "$LAST_DECISION_FILE.tmp.XXXXXX" 2>/dev/null) || return 0
    if printf '%s\n' "$decision_json" > "$temp_file"; then
        mv -f "$temp_file" "$LAST_DECISION_FILE" 2>/dev/null || rm -f "$temp_file"
    else
        rm -f "$temp_file"
    fi

    # Optionally append to decision log
    if [ "$DECISION_LOG_ENABLED" = "true" ]; then
        decision_log_append "$decision_json"
    fi
}

# Appends a decision record to the log file with rotation
decision_log_append() {
    local record="$1"
    local temp_file

    # Append the new record
    printf '%s\n' "$record" >> "$DECISION_LOG_FILE" 2>/dev/null || return 0

    # Check if rotation is needed
    local line_count
    line_count=$(wc -l < "$DECISION_LOG_FILE" 2>/dev/null | tr -d ' ')
    [ -n "$line_count" ] || return 0

    if [ "$line_count" -gt "$DECISION_LOG_MAX_LINES" ]; then
        # Rotate: keep last DECISION_LOG_MAX_LINES entries
        temp_file=$(mktemp "$DECISION_LOG_FILE.tmp.XXXXXX" 2>/dev/null) || return 0
        if tail -n "$DECISION_LOG_MAX_LINES" "$DECISION_LOG_FILE" > "$temp_file" 2>/dev/null; then
            mv -f "$temp_file" "$DECISION_LOG_FILE" 2>/dev/null || rm -f "$temp_file"
        else
            rm -f "$temp_file"
        fi
    fi
}

emit_decision() {
    local decision="$1"
    local reason="$2"

    # Persist decision before emitting (failures are silent)
    persist_decision "$decision" "$reason"

    # Emit the decision JSON to stdout
    jq -n --arg d "$decision" --arg r "$reason" '{"decision": $d, "reason": $r}'
}
