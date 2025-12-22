#!/bin/bash
# transcript.sh - Transcript validation and context extraction
#
# Provides helpers to validate transcript files and extract recent
# conversation context as a JSON array.

# Validates transcript file path
# Returns: error string (empty = ok)
validate_transcript_path() {
    local transcript_path="$1"
    if [ -z "$transcript_path" ]; then
        echo "No transcript path provided"
        return 0
    fi
    if [ ! -f "$transcript_path" ]; then
        echo "Transcript file not found"
        return 0
    fi
    if [ ! -r "$transcript_path" ]; then
        echo "Transcript file not readable"
        return 0
    fi
    if [ ! -s "$transcript_path" ]; then
        echo "Transcript file is empty"
        return 0
    fi
    echo ""
}

# Extracts recent valid NDJSON entries as a JSON array
# Args: transcript_path, context_lines (default 10)
# Returns: JSON array (or "[]" on failure)
extract_recent_context_json_array() {
    local transcript_path="$1"
    local context_lines="${2:-10}"

    # Read more lines than needed to ensure we get enough valid ones after filtering
    tail -n 50 "$transcript_path" 2>/dev/null | \
        grep -v '^[[:space:]]*$' | \
        while IFS= read -r line; do
            # Only output lines that are valid JSON
            printf '%s\n' "$line" | jq -e '.' >/dev/null 2>&1 && printf '%s\n' "$line"
        done | \
        tail -n "$context_lines" | \
        jq -s '.' 2>/dev/null
}
