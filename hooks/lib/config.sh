#!/bin/bash
# config.sh - Configuration defaults
#
# Loads default configuration values. Future versions will support
# per-project settings override.

load_defaults() {
    MAX_CONTINUATIONS=3
    THROTTLE_WINDOW_SECONDS=300
    TRANSCRIPT_CONTEXT_LINES=10
    CLAUDE_MODEL="haiku"
    CLAUDE_WORK_DIR="$HOME/.claude/double-shot-latte"

    # Decision persistence configuration (FTR-005)
    DECISION_DIR="$CLAUDE_WORK_DIR"
    LAST_DECISION_FILE="$DECISION_DIR/last_decision.json"
    DECISION_LOG_FILE="$DECISION_DIR/decision_log.jsonl"
    # Validate DECISION_LOG_MAX_LINES is numeric (fail closed to default 100)
    local _max_lines="${REDBULL_LOG_MAX_LINES:-100}"
    if [[ "$_max_lines" =~ ^[0-9]+$ ]] && [ "$_max_lines" -gt 0 ]; then
        DECISION_LOG_MAX_LINES="$_max_lines"
    else
        DECISION_LOG_MAX_LINES=100
    fi
    DECISION_LOG_ENABLED="${REDBULL_LOG_DECISIONS:-false}"
}

# Globals for persistence context (set during script execution)
PERSIST_SESSION_ID=""
PERSIST_EVALUATION_RESULT=""
