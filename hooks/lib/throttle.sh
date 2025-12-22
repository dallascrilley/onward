#!/bin/bash
# throttle.sh - Continuation throttling to prevent infinite loops
#
# Manages continuation throttling using file-based state.
# File format: <count>:<unix_epoch_seconds>
#
# Globals expected from caller:
# - CURRENT_TIME (unix timestamp)
# - MAX_CONTINUATIONS (optional, defaults to 3)
# - THROTTLE_WINDOW_SECONDS (optional, defaults to 300)
#
# Globals set by throttle_read:
# - CONTINUE_COUNT
# - LAST_CONTINUE_TIME

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
    local max_continues="${1:-${MAX_CONTINUATIONS:-3}}"
    local window_seconds="${2:-${THROTTLE_WINDOW_SECONDS:-300}}"
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
