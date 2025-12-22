#!/bin/bash
# emit.sh - Single point of stdout JSON output for hooks
#
# All hook decisions must go through this emitter to ensure:
# - Consistent JSON format
# - Only stdout contains JSON (no debug output)
# - Easy to test and mock
# - Decision persistence for debugging (FTR-005)
# - Stall metadata persistence (Phase 5)
#
# Stall metadata environment variables (optional):
# - PERSIST_STALL_RISK: 0-100 stall risk score
# - PERSIST_CONTEXT_HASH: 16-char context fingerprint

# Persists the decision to last_decision.json and optionally to decision_log.jsonl
persist_decision() {
    local decision="$1"
    local reason="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local dod_rules_count=0
    local dod_enforcement=""

    # Pseudocode: if running in judge mode, skip persistence to avoid overwriting user decisions
    if [ "${CLAUDE_HOOK_JUDGE_MODE:-false}" = "true" ]; then
        return 0
    fi

    # Ensure decision directory exists
    mkdir -p "$DECISION_DIR" 2>/dev/null || return 0

    if [ -n "${DEFINITION_OF_DONE:-}" ]; then
        dod_rules_count=$(printf '%s\n' "$DEFINITION_OF_DONE" | awk 'NF{count++} END{print count+0}')
        dod_enforcement="${DOD_ENFORCEMENT:-advisory}"
    fi

    # Stall metadata (Phase 5) - optional
    local stall_risk="${PERSIST_STALL_RISK:-}"
    local context_hash="${PERSIST_CONTEXT_HASH:-}"

    # Build the decision record with available context
    local decision_json
    if [ -n "$PERSIST_EVALUATION_RESULT" ] && [ "$PERSIST_EVALUATION_RESULT" != "null" ]; then
        # Pseudocode: if evaluation JSON is invalid, store it as a raw string instead
        if echo "$PERSIST_EVALUATION_RESULT" | jq -e . > /dev/null 2>&1; then
            decision_json=$(jq -n \
                --arg ts "$timestamp" \
                --arg sid "$PERSIST_SESSION_ID" \
                --arg dec "$decision" \
                --arg reason "$reason" \
                --argjson eval "$PERSIST_EVALUATION_RESULT" \
                --arg dod_enforcement "$dod_enforcement" \
                --argjson dod_rules_count "$dod_rules_count" \
                --arg stall_risk "$stall_risk" \
                --arg context_hash "$context_hash" \
                '{
                    timestamp: $ts,
                    session_id: $sid,
                    decision: $dec,
                    reason: $reason,
                    evaluation: $eval
                }
                | if $dod_rules_count > 0
                  then . + {dod_enforcement: $dod_enforcement, dod_rules_count: $dod_rules_count}
                  else .
                  end
                | if $stall_risk != ""
                  then . + {stall_risk: ($stall_risk | tonumber), context_hash: $context_hash}
                  else .
                  end') || return 0
        else
            decision_json=$(jq -n \
                --arg ts "$timestamp" \
                --arg sid "$PERSIST_SESSION_ID" \
                --arg dec "$decision" \
                --arg reason "$reason" \
                --arg eval_raw "$PERSIST_EVALUATION_RESULT" \
                --arg dod_enforcement "$dod_enforcement" \
                --argjson dod_rules_count "$dod_rules_count" \
                --arg stall_risk "$stall_risk" \
                --arg context_hash "$context_hash" \
                '{
                    timestamp: $ts,
                    session_id: $sid,
                    decision: $dec,
                    reason: $reason,
                    evaluation_raw: $eval_raw
                }
                | if $dod_rules_count > 0
                  then . + {dod_enforcement: $dod_enforcement, dod_rules_count: $dod_rules_count}
                  else .
                  end
                | if $stall_risk != ""
                  then . + {stall_risk: ($stall_risk | tonumber), context_hash: $context_hash}
                  else .
                  end') || return 0
        fi
    else
        decision_json=$(jq -n \
            --arg ts "$timestamp" \
            --arg sid "$PERSIST_SESSION_ID" \
            --arg dec "$decision" \
            --arg reason "$reason" \
            --arg dod_enforcement "$dod_enforcement" \
            --argjson dod_rules_count "$dod_rules_count" \
            --arg stall_risk "$stall_risk" \
            --arg context_hash "$context_hash" \
            '{
                timestamp: $ts,
                session_id: $sid,
                decision: $dec,
                reason: $reason
            }
            | if $dod_rules_count > 0
              then . + {dod_enforcement: $dod_enforcement, dod_rules_count: $dod_rules_count}
              else .
              end
            | if $stall_risk != ""
              then . + {stall_risk: ($stall_risk | tonumber), context_hash: $context_hash}
              else .
              end') || return 0
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

# Helper to build stall metadata JSON fragment
# Args: stall_risk (0-100), context_hash (string)
# Returns: JSON fragment for inclusion in decision record
emit_stall_metadata() {
    local stall_risk="$1"
    local context_hash="$2"

    if [ -z "$stall_risk" ] && [ -z "$context_hash" ]; then
        echo "{}"
        return 0
    fi

    jq -n \
        --argjson stall_risk "${stall_risk:-0}" \
        --arg context_hash "${context_hash:-}" \
        '{stall_risk: $stall_risk, context_hash: $context_hash}'
}
