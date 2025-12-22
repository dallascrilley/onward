#!/bin/bash
# throttle.sh - Continuation throttling to prevent infinite loops
#
# Manages continuation throttling using file-based state.
# File format: <count>:<unix_epoch_seconds>:<context_hash> (v2)
# Legacy format: <count>:<unix_epoch_seconds> (v1, still supported)
#
# Globals expected from caller:
# - CURRENT_TIME (unix timestamp)
# - MAX_CONTINUATIONS (optional, defaults to 3)
# - THROTTLE_WINDOW_SECONDS (optional, defaults to 300)
#
# Globals set by throttle_read:
# - CONTINUE_COUNT
# - LAST_CONTINUE_TIME
# - CONTEXT_HASH (empty for legacy format)

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

# Reads throttle file, sets CONTINUE_COUNT, LAST_CONTINUE_TIME, and CONTEXT_HASH globals
throttle_read() {
    local throttle_file="$1"
    CONTINUE_COUNT=0
    LAST_CONTINUE_TIME=0
    CONTEXT_HASH=""
    [ -f "$throttle_file" ] || return 0
    local throttle_data
    throttle_data=$(<"$throttle_file")
    [ -n "$throttle_data" ] || return 0
    
    if echo "$throttle_data" | jq empty 2>/dev/null; then
        local count
        local timestamp
        local context_hash
        count=$(echo "$throttle_data" | jq -r '.continue_count // empty')
        timestamp=$(echo "$throttle_data" | jq -r '.last_continue_time // empty')
        context_hash=$(echo "$throttle_data" | jq -r '.context_hash // empty')
        
        if [ -z "$count" ] || [ -z "$timestamp" ]; then
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
        CONTEXT_HASH="$context_hash"
        return 0
    fi
    
    local count
    local timestamp
    local context_hash
    local extra
    IFS=':' read -r count timestamp context_hash extra <<<"$throttle_data"
    if [ -z "$count" ] || [ -z "$timestamp" ]; then
        throttle_clear "$throttle_file"
        return 0
    fi
    if [ -n "$extra" ]; then
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
    CONTEXT_HASH="${context_hash:-}"
}

throttle_write() {
    local throttle_file="$1"
    local count="$2"
    local timestamp="$3"
    local context_hash="${4:-}"
    local temp_file
    temp_file=$(mktemp "${throttle_file}.tmp.XXXXXX") || return 1
    
    local data
    if [ -n "$context_hash" ]; then
        data=$(jq -n \
            --argjson count "$count" \
            --argjson timestamp "$timestamp" \
            --arg hash "$context_hash" \
            '{continue_count: $count, last_continue_time: $timestamp, context_hash: $hash}')
    else
        data=$(jq -n \
            --argjson count "$count" \
            --argjson timestamp "$timestamp" \
            '{continue_count: $count, last_continue_time: $timestamp}')
    fi
    
    if ! printf '%s\n' "$data" > "$temp_file"; then
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

# Returns the stored context hash (after throttle_read)
# Returns: context hash string or empty
throttle_get_context_hash() {
    echo "${CONTEXT_HASH:-}"
}

# Compute context hash from transcript context
# Extracts last assistant message content and hashes it
# Args: transcript_context (JSON array string)
# Returns: first 16 chars of SHA256 hash
compute_context_hash() {
    local context="$1"
    [ -n "$context" ] || return 1

    # Extract last assistant message content for hashing
    # This normalizes the context to avoid false progress from metadata/timestamp changes
    local content
    content=$(printf '%s' "$context" | jq -r '[.[] | select(.role=="assistant")] | last | .content // empty' 2>/dev/null)
    [ -n "$content" ] || return 1

    # Compute SHA256 hash
    local hash
    if command -v shasum >/dev/null 2>&1; then
        hash=$(printf '%s' "$content" | shasum -a 256 2>/dev/null | cut -d' ' -f1)
    elif command -v sha256sum >/dev/null 2>&1; then
        hash=$(printf '%s' "$content" | sha256sum 2>/dev/null | cut -d' ' -f1)
    else
        # No hash command available
        return 1
    fi

    # Return first 16 chars for readability
    echo "${hash:0:16}"
}
