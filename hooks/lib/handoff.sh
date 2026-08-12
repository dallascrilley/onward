#!/bin/bash
# handoff.sh - Write handoff snapshot on approved stop
#
# Writes .claude/handoff.md in the current working directory when a session
# ends with an approved stop. Provides context for the next session.
#
# Silent failures - never breaks the hook.

# Max characters per message content in the context section
HANDOFF_MAX_CONTENT_CHARS=200
# Max lines for git diff output
HANDOFF_MAX_GIT_FILES=50

# Write handoff snapshot if conditions are met
# Args: decision session_id reason recent_context_json_array
handoff_write_if_needed() {
    local decision="$1"
    local session_id="$2"
    local reason="$3"
    local recent_context="$4"

    # Only write on approved stops (not blocked)
    [ "$decision" = "approve" ] || return 0

    # Never run in judge mode
    [ "${CLAUDE_HOOK_JUDGE_MODE:-false}" = "true" ] && return 0

    # Need session_id and reason at minimum
    [ -n "$session_id" ] || return 0
    [ -n "$reason" ] || return 0

    # Build and write the handoff
    _handoff_build_and_write "$session_id" "$reason" "$recent_context"
}

# Internal: Build and write the handoff markdown
_handoff_build_and_write() {
    local session_id="$1"
    local reason="$2"
    local recent_context="$3"
    local timestamp
    local handoff_content
    local handoff_dir=".claude"
    local handoff_file="$handoff_dir/handoff.md"

    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Ensure .claude directory exists
    mkdir -p "$handoff_dir" 2>/dev/null || return 0

    # Build the handoff content
    handoff_content="# Onward Handoff

**Session:** $session_id
**Stopped:** $timestamp

## Stop Reason

$reason
"

    # Add recent context if available
    if [ -n "$recent_context" ] && [ "$recent_context" != "null" ] && [ "$recent_context" != "[]" ]; then
        local context_section
        context_section=$(_handoff_format_context "$recent_context")
        if [ -n "$context_section" ]; then
            handoff_content="${handoff_content}
## Recent Context

$context_section"
        fi
    fi

    # Add git info if in a git repo
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local git_section
        git_section=$(_handoff_git_section)
        if [ -n "$git_section" ]; then
            handoff_content="${handoff_content}
## Git Status

$git_section"
        fi
    fi

    # Write atomically
    local temp_file
    temp_file=$(mktemp "$handoff_file.tmp.XXXXXX" 2>/dev/null) || return 0
    if printf '%s\n' "$handoff_content" > "$temp_file"; then
        mv -f "$temp_file" "$handoff_file" 2>/dev/null || rm -f "$temp_file"
    else
        rm -f "$temp_file"
    fi
}

# Internal: Format recent context as markdown list
# Parses JSON once and iterates results to avoid repeated jq calls
_handoff_format_context() {
    local context_json="$1"
    local result=""

    # Validate jq is available
    command -v jq >/dev/null 2>&1 || return 0

    # Parse all messages in a single jq call: "role\tcontent\n" per message
    # Using tab as delimiter since it's unlikely in content
    local parsed
    parsed=$(echo "$context_json" | jq -r '.[] | "\(.role // "unknown")\t\(.content // "")"' 2>/dev/null) || return 0
    [ -n "$parsed" ] || return 0

    # Iterate over parsed lines
    while IFS=$'\t' read -r role content; do
        [ -n "$role" ] || continue

        # Truncate content if too long
        local truncated
        if [ ${#content} -gt "$HANDOFF_MAX_CONTENT_CHARS" ]; then
            truncated="${content:0:$HANDOFF_MAX_CONTENT_CHARS}..."
        else
            truncated="$content"
        fi

        # Replace newlines with spaces for single-line display
        truncated=$(printf '%s' "$truncated" | tr '\n' ' ' | tr -s ' ')

        result="${result}- **${role}:** ${truncated}
"
    done <<< "$parsed"

    printf '%s' "$result"
}

# Internal: Build git status section
_handoff_git_section() {
    local branch result=""

    # Get current branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        result="**Branch:** $branch
"
    fi

    # Get all changed files: staged + unstaged + untracked
    # Combine and dedupe with sort -u
    local changed_files
    changed_files=$({
        git diff --name-only 2>/dev/null
        git diff --staged --name-only 2>/dev/null
    } | sort -u | head -n "$HANDOFF_MAX_GIT_FILES")

    if [ -n "$changed_files" ]; then
        result="${result}
**Changed files:**
"
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            result="${result}- $file
"
        done <<< "$changed_files"
    fi

    printf '%s' "$result"
}
