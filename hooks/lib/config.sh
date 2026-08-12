#!/bin/bash
# config.sh - Configuration defaults with env var overrides
#
# All settings have safe defaults. Env vars allow runtime override.
# Invalid numeric values are ignored (fail closed to defaults).

# Helper: validate and apply numeric env var override
# Usage: _apply_numeric_override VAR_NAME DEFAULT ENV_VAR_NAME [MIN_VALUE]
_apply_numeric_override() {
    local var_name="$1"
    local default="$2"
    local env_value="$3"
    local min_value="${4:-1}"

    if [[ "$env_value" =~ ^[0-9]+$ ]] && [ "$env_value" -ge "$min_value" ]; then
        eval "$var_name=\"$env_value\""
    else
        eval "$var_name=\"$default\""
    fi
}

load_defaults() {
    # === Throttle Configuration ===
    # Max continuation cycles before forcing stop
    _apply_numeric_override MAX_CONTINUATIONS 3 "${ONWARD_THROTTLE_LIMIT:-3}" 1
    # Time window in seconds for throttle counting
    _apply_numeric_override THROTTLE_WINDOW_SECONDS 300 "${ONWARD_THROTTLE_WINDOW_SECONDS:-300}" 10

    # === Judge Configuration ===
    # Number of transcript lines to send to judge
    _apply_numeric_override TRANSCRIPT_CONTEXT_LINES 10 "${ONWARD_TRANSCRIPT_CONTEXT_LINES:-10}" 1
    # Model for judge evaluation (validated models: haiku, sonnet, opus)
    local _model="${ONWARD_JUDGE_MODEL:-haiku}"
    case "$_model" in
        haiku|sonnet|opus) CLAUDE_MODEL="$_model" ;;
        *) CLAUDE_MODEL="haiku" ;;  # Invalid model, use default
    esac

    # === Dry-Run Mode ===
    # When true: evaluate but always approve stop (never blocks)
    case "${ONWARD_DRY_RUN:-false}" in
        true|TRUE|1) ONWARD_DRY_RUN=true ;;
        *) ONWARD_DRY_RUN=false ;;
    esac

    # === State Directory ===
    CLAUDE_WORK_DIR="${ONWARD_STATE_DIR:-$HOME/.claude/onward}"

    # === Decision Persistence (FTR-005) ===
    DECISION_DIR="$CLAUDE_WORK_DIR"
    LAST_DECISION_FILE="$DECISION_DIR/last_decision.json"
    DECISION_LOG_FILE="$DECISION_DIR/decision_log.jsonl"
    _apply_numeric_override DECISION_LOG_MAX_LINES 500 "${ONWARD_LOG_MAX_LINES:-500}" 1
    # Decision logging enabled by default for observability
    case "${ONWARD_LOG_DECISIONS:-true}" in
        false|FALSE|0) DECISION_LOG_ENABLED=false ;;
        *) DECISION_LOG_ENABLED=true ;;
    esac
}

# Globals for persistence context (set during script execution)
PERSIST_SESSION_ID=""
PERSIST_EVALUATION_RESULT=""
