#!/bin/bash

# Explain Last Decision - CLI tool for viewing the most recent judge decision
# Usage: ./scripts/explain.sh [-v|--verbose] [-j|--json]

set -euo pipefail

# Configuration (allow env overrides for custom work dirs)
DECISION_DIR="${DECISION_DIR:-${CLAUDE_WORK_DIR:-$HOME/.claude/redbull}}"
LAST_DECISION_FILE="${LAST_DECISION_FILE:-$DECISION_DIR/last_decision.json}"

# Parse arguments
VERBOSE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Display the last judge decision from the redbull plugin."
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show full decision details including evaluation"
            echo "  -j, --json       Output raw JSON (useful for scripting)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Files:"
            echo "  Last decision:   $LAST_DECISION_FILE"
            echo "  Decision log:    $DECISION_DIR/decision_log.jsonl (if enabled)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

# Check if decision file exists
if [[ ! -f "$LAST_DECISION_FILE" ]]; then
    echo "No decision history found."
    echo ""
    echo "The judge hasn't made any decisions yet, or the decision file was cleared."
    echo "Expected location: $LAST_DECISION_FILE"
    exit 0
fi

# Read the decision file
DECISION_JSON=$(cat "$LAST_DECISION_FILE")

# Validate JSON
if ! echo "$DECISION_JSON" | jq empty 2>/dev/null; then
    echo "Error: Decision file contains invalid JSON." >&2
    exit 1
fi

# JSON output mode - just dump the file
if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "$DECISION_JSON" | jq '.'
    exit 0
fi

# Extract fields
TIMESTAMP=$(echo "$DECISION_JSON" | jq -r '.timestamp // "unknown"')
SESSION_ID=$(echo "$DECISION_JSON" | jq -r '.session_id // "unknown"')
DECISION=$(echo "$DECISION_JSON" | jq -r '.decision // "unknown"')
REASON=$(echo "$DECISION_JSON" | jq -r '.reason // "No reason provided"')

# Determine human-readable decision
if [[ "$DECISION" == "block" ]]; then
    DECISION_LABEL="CONTINUE"
    DECISION_DESC="(blocked stop, work continues)"
elif [[ "$DECISION" == "approve" ]]; then
    DECISION_LABEL="STOP"
    DECISION_DESC="(approved stop)"
else
    DECISION_LABEL="UNKNOWN"
    DECISION_DESC="($DECISION)"
fi

# Format timestamp for display (if it's ISO format)
if [[ "$TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
    DISPLAY_TIME="$TIMESTAMP"
else
    DISPLAY_TIME="$TIMESTAMP"
fi

# Truncate session ID for display (show first 12 chars)
if [[ ${#SESSION_ID} -gt 12 ]]; then
    SHORT_SESSION="${SESSION_ID:0:12}..."
else
    SHORT_SESSION="$SESSION_ID"
fi

# Print formatted output
echo "Last Decision: $DECISION_LABEL $DECISION_DESC"
echo "Timestamp:     $DISPLAY_TIME"
echo "Session:       $SHORT_SESSION"
echo ""
echo "Reasoning:"

# Word-wrap the reason at ~70 characters with indentation
echo "$REASON" | fold -s -w 70 | sed 's/^/  /'

# Verbose mode: show evaluation details
if [[ "$VERBOSE" == "true" ]]; then
    echo ""
    echo "---"
    echo ""

    # Check if evaluation field exists
    EVAL_EXISTS=$(echo "$DECISION_JSON" | jq 'has("evaluation")')
    EVAL_RAW_EXISTS=$(echo "$DECISION_JSON" | jq 'has("evaluation_raw")')
    if [[ "$EVAL_EXISTS" == "true" ]]; then
        SHOULD_CONTINUE=$(echo "$DECISION_JSON" | jq -r '.evaluation.should_continue // "N/A"')
        EVAL_REASONING=$(echo "$DECISION_JSON" | jq -r '.evaluation.reasoning // "N/A"')

        echo "Evaluation Details:"
        echo "  should_continue: $SHOULD_CONTINUE"
        echo ""
        echo "  Claude's reasoning:"
        echo "$EVAL_REASONING" | fold -s -w 66 | sed 's/^/    /'

        # v2 fields (optional - only display if present)
        CONFIDENCE=$(echo "$DECISION_JSON" | jq -r '.evaluation.confidence // empty')
        CATEGORY=$(echo "$DECISION_JSON" | jq -r '.evaluation.decision_category // empty')
        RISK_LEVEL=$(echo "$DECISION_JSON" | jq -r '.evaluation.risk_level // empty')
        SIGNALS=$(echo "$DECISION_JSON" | jq -r '.evaluation.signals // empty')
        REASONS=$(echo "$DECISION_JSON" | jq -r '.evaluation.reasons // empty')

        # Only show v2 section if at least one v2 field exists
        if [[ -n "$CONFIDENCE" || -n "$CATEGORY" || -n "$RISK_LEVEL" || -n "$SIGNALS" ]]; then
            echo ""
            echo "v2 Metadata:"

            if [[ -n "$CONFIDENCE" && "$CONFIDENCE" != "null" ]]; then
                # Format confidence as percentage
                CONFIDENCE_PCT=$(echo "$CONFIDENCE * 100" | bc 2>/dev/null | cut -d. -f1)
                if [[ -n "$CONFIDENCE_PCT" ]]; then
                    echo "  Confidence:      ${CONFIDENCE_PCT}% ($CONFIDENCE)"
                else
                    echo "  Confidence:      $CONFIDENCE"
                fi
            fi

            if [[ -n "$CATEGORY" && "$CATEGORY" != "null" ]]; then
                echo "  Category:        $CATEGORY"
            fi

            if [[ -n "$RISK_LEVEL" && "$RISK_LEVEL" != "null" ]]; then
                echo "  Risk Level:      $RISK_LEVEL"
            fi

            if [[ -n "$SIGNALS" && "$SIGNALS" != "null" && "$SIGNALS" != "[]" ]]; then
                echo "  Signals:"
                echo "$DECISION_JSON" | jq -r '.evaluation.signals[]? // empty' | sed 's/^/    - /'
            fi

            if [[ -n "$REASONS" && "$REASONS" != "null" && "$REASONS" != "[]" ]]; then
                echo "  Reasons:"
                echo "$DECISION_JSON" | jq -r '.evaluation.reasons[]? // empty' | sed 's/^/    - /'
            fi
        fi

        DOD_ENFORCEMENT=$(echo "$DECISION_JSON" | jq -r '.dod_enforcement // empty')
        DOD_RULES_COUNT=$(echo "$DECISION_JSON" | jq -r '.dod_rules_count // empty')
        if [[ -n "$DOD_RULES_COUNT" && "$DOD_RULES_COUNT" != "null" && "$DOD_RULES_COUNT" != "0" ]]; then
            echo ""
            echo "DoD:"
            echo "  DoD Mode:      $DOD_ENFORCEMENT"
            echo "  DoD Rules:     $DOD_RULES_COUNT"
        fi

        # Stall Detection section (Phase 5)
        STALL_RISK=$(echo "$DECISION_JSON" | jq -r '.stall_risk // empty')
        STALL_CONTEXT_HASH=$(echo "$DECISION_JSON" | jq -r '.context_hash // empty')
        if [[ -n "$STALL_RISK" && "$STALL_RISK" != "null" ]]; then
            echo ""
            echo "Stall Detection:"
            echo "  Risk Score:    $STALL_RISK/100"

            # Status display based on risk level
            if [[ "$STALL_RISK" -gt 70 ]]; then
                echo "  Status:        HIGH RISK"
                echo "  Recommendation: Consider manual stop or reframe work"
            elif [[ "$STALL_RISK" -gt 40 ]]; then
                echo "  Status:        MODERATE RISK"
                echo "  Recommendation: Monitor for repeated patterns"
            else
                echo "  Status:        Low risk"
            fi

            if [[ -n "$STALL_CONTEXT_HASH" && "$STALL_CONTEXT_HASH" != "null" ]]; then
                echo "  Context Hash:  ${STALL_CONTEXT_HASH:0:16}..."
            fi
        fi

    elif [[ "$EVAL_RAW_EXISTS" == "true" ]]; then
        # evaluation_raw exists when the evaluation response wasn't valid JSON
        EVAL_RAW=$(echo "$DECISION_JSON" | jq -r '.evaluation_raw // "N/A"')
        echo "Evaluation Details:"
        echo "  (stored as raw text - evaluation response was not valid JSON)"
        echo ""
        echo "  Raw evaluation:"
        echo "$EVAL_RAW" | fold -s -w 66 | sed 's/^/    /'
    else
        # List available fields to help debug why evaluation is missing
        AVAILABLE_FIELDS=$(echo "$DECISION_JSON" | jq -r 'keys | join(", ")')
        echo "Evaluation details not available (early exit decision)"
        echo "  Available fields: $AVAILABLE_FIELDS"
        echo ""
        echo "  This usually means the hook exited before calling the Claude evaluator"
        echo "  (e.g., throttle limit, missing transcript, disabled by settings)"
    fi

    echo ""
    echo "Full Session ID: $SESSION_ID"
fi
