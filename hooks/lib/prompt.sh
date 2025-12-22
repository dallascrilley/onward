#!/bin/bash
# prompt.sh - Project rules injection for judge prompts
#
# Allows per-project customization of judge behavior via rules files.
# Rules are appended to the evaluation prompt to guide the judge.

# Maximum rules file size (8KB) to prevent prompt bloat
MAX_RULES_SIZE=8192

# Get the project rules file path
# Search order: REDBULL_PROJECT_RULES_PATH > .redbull/rules.md > .claude/redbull-rules.md
_get_project_rules_file() {
    # Explicit path takes precedence
    if [ -n "$REDBULL_PROJECT_RULES_PATH" ]; then
        if [ -r "$REDBULL_PROJECT_RULES_PATH" ]; then
            echo "$REDBULL_PROJECT_RULES_PATH"
            return 0
        fi
        return 1  # Explicit path not readable
    fi

    # Check standard locations
    local locations=(
        ".redbull/rules.md"
        ".claude/redbull-rules.md"
    )

    for loc in "${locations[@]}"; do
        if [ -r "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done

    return 1  # No rules file found
}

# Load and return project rules content (truncated if needed)
# Returns: rules content or empty string if no rules
get_project_rules() {
    local rules_file
    rules_file=$(_get_project_rules_file) || return 0

    local content
    content=$(cat "$rules_file" 2>/dev/null) || return 0
    [ -z "$content" ] && return 0

    local size=${#content}
    if [ "$size" -gt "$MAX_RULES_SIZE" ]; then
        # Truncate and add marker
        printf '%s\n...(truncated at %d bytes)' "${content:0:$MAX_RULES_SIZE}" "$MAX_RULES_SIZE"
    else
        printf '%s' "$content"
    fi
}

# Build evaluation prompt with optional project rules
# Usage: EVALUATION_PROMPT=$(build_evaluation_prompt_with_rules "$RECENT_CONTEXT")
build_evaluation_prompt_with_rules() {
    local context="$1"
    local base_prompt
    local rules

    # Get base prompt from judge.sh
    base_prompt=$(build_evaluation_prompt "$context")

    # Get project rules
    rules=$(get_project_rules)

    if [ -n "$rules" ]; then
        cat <<EOF
$base_prompt

---

ADDITIONAL PROJECT RULES (apply these to your decision):

$rules
EOF
    else
        echo "$base_prompt"
    fi
}
