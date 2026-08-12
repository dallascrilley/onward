#!/bin/bash
# ignore.sh - Ignore pattern bypass for Stop hook
#
# Allows bypassing the judge for known scenarios where stopping is appropriate.
# Patterns are literal substrings (not regex) matched against transcript content.

# Get the ignore patterns file path
# Search order: ONWARD_IGNORE_PATTERNS_PATH > .onward/ignore.txt > .claude/onward-ignore.txt
_get_ignore_patterns_file() {
    # Explicit path takes precedence
    if [ -n "$ONWARD_IGNORE_PATTERNS_PATH" ]; then
        if [ -r "$ONWARD_IGNORE_PATTERNS_PATH" ]; then
            echo "$ONWARD_IGNORE_PATTERNS_PATH"
            return 0
        fi
        return 1  # Explicit path not readable
    fi

    # Check standard locations
    local locations=(
        ".onward/ignore.txt"
        ".claude/onward-ignore.txt"
    )

    for loc in "${locations[@]}"; do
        if [ -r "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done

    return 1  # No patterns file found
}

# Check if transcript matches any ignore pattern
# Args: $1 = recent_context_json_array
# Returns: echoes matched pattern if found, empty otherwise
# Exit code: 0 if match found, 1 if no match
ignore_should_approve_stop() {
    local context_json="$1"

    # Get patterns file
    local patterns_file
    patterns_file=$(_get_ignore_patterns_file) || return 1

    # Extract transcript text (flatten all content to single string)
    local transcript_text
    transcript_text=$(echo "$context_json" | jq -r '.[].content // empty' 2>/dev/null | tr '\n' ' ') || return 1
    [ -z "$transcript_text" ] && return 1

    # Check each pattern (non-empty, non-comment lines)
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        # Skip empty lines and comments
        [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]] && continue

        # Literal substring match (grep -F, -- prevents patterns starting with - from being interpreted as options)
        if printf '%s' "$transcript_text" | grep -qF -- "$pattern"; then
            echo "$pattern"
            return 0
        fi
    done < "$patterns_file"

    return 1  # No match
}
