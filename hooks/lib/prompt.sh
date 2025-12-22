#!/bin/bash
# prompt.sh - Project rules injection for judge prompts
#
# Allows per-project customization of judge behavior via rules files.
# Rules are appended to the evaluation prompt to guide the judge.
# Also handles Definition of Done (DoD) injection from settings.

# Source settings.sh for DoD config access
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=settings.sh
source "$SCRIPT_DIR/settings.sh" 2>/dev/null || true

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

# Build DoD section based on enforcement mode
# Returns: DoD prompt section or empty string if no DoD rules
_build_dod_section() {
    # Check if DEFINITION_OF_DONE is set and non-empty
    [ -z "$DEFINITION_OF_DONE" ] && return 0

    local enforcement="${DOD_ENFORCEMENT:-advisory}"

    if [ "$enforcement" = "strict" ]; then
        cat <<EOF

---

DEFINITION OF DONE (STRICT MODE):

The user has defined these MANDATORY completion criteria:

$DEFINITION_OF_DONE

STRICT MODE: Only approve STOP if (a) the DoD is explicitly met WITH evidence (test output, verification, etc.), OR (b) an unresolvable blocker requires the user.
If criteria appear unmet or unclear, bias toward should_continue=true.
EOF
    else
        # Default: advisory mode
        cat <<EOF

---

DEFINITION OF DONE (ADVISORY MODE):

The user has defined these completion criteria:

$DEFINITION_OF_DONE

ADVISORY MODE: Consider these criteria; if they appear unmet, lean toward continuing. Otherwise keep the base rule: Default to STOP when uncertain.
EOF
    fi
}

# Build evaluation prompt with optional project rules
# Usage: EVALUATION_PROMPT=$(build_evaluation_prompt_with_rules "$RECENT_CONTEXT")
build_evaluation_prompt_with_rules() {
    local context="$1"
    local base_prompt
    local rules
    local dod_section

    # Get base prompt from judge.sh
    base_prompt=$(build_evaluation_prompt "$context")

    # Get project rules
    rules=$(get_project_rules)

    # Get DoD section (settings should already be loaded)
    dod_section=$(_build_dod_section)

    if [ -n "$rules" ]; then
        if [ -n "$dod_section" ]; then
            # Both rules and DoD
            cat <<EOF
$base_prompt

---

ADDITIONAL PROJECT RULES (apply these to your decision):

$rules
$dod_section
EOF
        else
            # Rules only, no DoD
            cat <<EOF
$base_prompt

---

ADDITIONAL PROJECT RULES (apply these to your decision):

$rules
EOF
        fi
    else
        if [ -n "$dod_section" ]; then
            # DoD only, no rules
            echo "$base_prompt"
            echo "$dod_section"
        else
            # Neither rules nor DoD
            echo "$base_prompt"
        fi
    fi
}
