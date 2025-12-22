#!/bin/bash
# judge.sh - Claude-based continuation evaluation
#
# Calls a separate Claude instance to judge whether the assistant
# has more autonomous work to do.

# === Exported Prompt/Schema Definitions (used by both production and snapshot extraction) ===
JUDGE_JSON_SCHEMA='{"type":"object","properties":{"should_continue":{"type":"boolean"},"reasoning":{"type":"string"}},"required":["should_continue","reasoning"]}'

JUDGE_SYSTEM_PROMPT="You are a conversation state classifier. Your only job is to analyze conversation transcripts and determine if the assistant has more autonomous work to do. You output structured JSON. You do not write code or use tools."

# Build evaluation prompt with conversation context
# Usage: EVALUATION_PROMPT=$(build_evaluation_prompt "$RECENT_CONTEXT")
build_evaluation_prompt() {
    local context="$1"
    cat <<EOF
Analyze this conversation and determine: Does the assistant have more autonomous work to do RIGHT NOW?

Conversation:
$context

CONTINUE (should_continue: true) ONLY IF the assistant explicitly states what it will do next:
- Phrases indicating intent to continue (e.g., 'Next I need to...', 'Now I'll...', 'Moving on to...')
- Incomplete todo list with remaining items marked pending
- Stated follow-up tasks not yet performed

STOP (should_continue: false) in ALL other cases:

1. TASK COMPLETION - The assistant indicates work is finished:
   - Completion statements (done, complete, finished, ready, all set)
   - Summary of accomplished work with no stated next steps
   - Confirming something is working/verified/installed

2. QUESTIONS - The assistant needs user input:
   - Asking for approval, decisions, clarification, or confirmation
   - Offering optional actions (e.g., 'Want me to...?', 'Should I also...?')
   - Note: Mid-task continuation questions (e.g., 'Should I continue?' when work is ongoing) = CONTINUE

3. BLOCKERS - The assistant cannot proceed:
   - Unresolved errors or missing information
   - Uncertainty about requirements

KEY: If the assistant is WAITING for the user (whether after completing work OR asking a question), that means STOP. Waiting ≠ more autonomous work to do.

Default to STOP when uncertain.
EOF
}

# Evaluates whether continuation is appropriate
# Args: recent_context (JSON array), claude_model, claude_work_dir
# Returns: structured_output JSON (or empty string on failure)
judge_should_continue() {
    local recent_context="$1"
    local claude_model="$2"
    local claude_work_dir="$3"

    mkdir -p "$claude_work_dir"

    local evaluation_prompt
    # Use rules-enhanced prompt if prompt.sh is sourced, otherwise base prompt
    if type build_evaluation_prompt_with_rules &>/dev/null; then
        evaluation_prompt=$(build_evaluation_prompt_with_rules "$recent_context")
    else
        evaluation_prompt=$(build_evaluation_prompt "$recent_context")
    fi

    local claude_response
    claude_response=$(printf '%s' "$evaluation_prompt" | (cd "$claude_work_dir" && CLAUDE_HOOK_JUDGE_MODE=true claude --print --model "$claude_model" --output-format json --json-schema "$JUDGE_JSON_SCHEMA" --system-prompt "$JUDGE_SYSTEM_PROMPT" --disallowedTools '*') 2>/dev/null) || return 1

    # Handle both streaming array format and single object format
    printf '%s' "$claude_response" | jq -c 'if type=="array" then .[] else . end | select(has("structured_output")) | .structured_output // empty' 2>/dev/null
}

# === Permission Language Prefilter (Phase 1) ===
# Detects obvious permission-seeking or user-choice patterns in last assistant message
# Returns pattern type or empty string if no match

# Detect permission language patterns from recent context
# Args: recent_context (JSON array via stdin or $1)
# Returns: pattern type (permission_seeking, explicit_choice_required, optional_offer) or empty
detect_permission_language() {
    local recent_context="$1"

    # If no arg, try reading from stdin
    if [ -z "$recent_context" ]; then
        recent_context=$(cat)
    fi

    # Extract last assistant message
    local last_assistant
    last_assistant=$(printf '%s' "$recent_context" | jq -r '[.[] | select(.role=="assistant")] | last | .content // empty' 2>/dev/null)

    # No assistant message found
    [ -z "$last_assistant" ] && return 1

    # Must have question mark for high precision
    if ! grep -q '\?' <<< "$last_assistant"; then
        return 1
    fi

    # PERMISSION-SEEKING patterns → BLOCK (continue work)
    # "should i continue", "shall i proceed", "is it ok if i", "ready to proceed"
    if grep -Eqi "should i continue|shall i proceed|is it (ok|alright|fine) if i|ready to proceed" <<< "$last_assistant"; then
        echo "permission_seeking"
        return 0
    fi

    # EXPLICIT CHOICE REQUIRED patterns → APPROVE (stop, wait for user)
    # "which...prefer", "choose", "which option"
    if grep -Eqi "(which.*prefer|prefer.*which|choose|which option)" <<< "$last_assistant"; then
        echo "explicit_choice_required"
        return 0
    fi

    # "does this look/seem/sound good", "is this ok"
    if grep -Eqi "does this.*(look|seem|sound).*(good|ok|correct|work)|is this.*(ok|correct)" <<< "$last_assistant"; then
        echo "explicit_choice_required"
        return 0
    fi

    # OPTIONAL WORK patterns → APPROVE (stop, wait for user)
    # "want me to" or "should i also" with explicit optional framing
    if grep -Eqi "(want me to|should i also).*(optional|nice.?to.?have|if you want)" <<< "$last_assistant"; then
        echo "optional_offer"
        return 0
    fi

    # No pattern matched - fall through to judge
    return 1
}

# Map detected pattern to decision
# Args: pattern type
# Returns: decision (block, approve, or empty for unknown)
permission_language_decision() {
    local pattern="$1"

    case "$pattern" in
        permission_seeking)
            # Work is ongoing, assistant asking if it should continue → BLOCK stop (continue)
            echo "block"
            ;;
        explicit_choice_required|optional_offer)
            # Waiting for user decision or optional offer → APPROVE stop
            echo "approve"
            ;;
        *)
            # Unknown pattern → fall back to judge
            echo ""
            ;;
    esac
}
