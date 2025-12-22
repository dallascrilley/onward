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
    DECISION_LOG_MAX_LINES="${REDBULL_LOG_MAX_LINES:-100}"
    DECISION_LOG_ENABLED="${REDBULL_LOG_DECISIONS:-false}"
}

# Globals for persistence context (set during script execution)
PERSIST_SESSION_ID=""
PERSIST_EVALUATION_RESULT=""
