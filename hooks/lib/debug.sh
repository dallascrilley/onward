#!/bin/bash
# debug.sh - Structured debug logging (opt-in via REDBULL_DEBUG=true)
#
# Logs metadata only (never transcript content or secrets) to stderr as JSON.

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
