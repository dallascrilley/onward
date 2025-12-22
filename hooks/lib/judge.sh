#!/bin/bash
# judge.sh - Claude-based continuation evaluation
#
# Calls a separate Claude instance to judge whether the assistant
# has more autonomous work to do.

# Evaluates whether continuation is appropriate
# Args: recent_context (JSON array), claude_model, claude_work_dir
# Returns: structured_output JSON (or empty string on failure)
judge_should_continue() {
    local recent_context="$1"
    local claude_model="$2"
    local claude_work_dir="$3"

    local json_schema='{"type":"object","properties":{"should_continue":{"type":"boolean"},"reasoning":{"type":"string"}},"required":["should_continue","reasoning"]}'
    local system_prompt="You are a conversation state classifier. Your only job is to analyze conversation transcripts and determine if the assistant has more autonomous work to do. You output structured JSON. You do not write code or use tools."

    mkdir -p "$claude_work_dir"

    local evaluation_prompt
    evaluation_prompt="Analyze this conversation and determine: Does the assistant have more autonomous work to do RIGHT NOW?

Conversation:
$recent_context

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

Default to STOP when uncertain."

    local claude_response
    claude_response=$(printf '%s' "$evaluation_prompt" | (cd "$claude_work_dir" && CLAUDE_HOOK_JUDGE_MODE=true claude --print --model "$claude_model" --output-format json --json-schema "$json_schema" --system-prompt "$system_prompt" --disallowedTools '*') 2>/dev/null) || return 1

    printf '%s' "$claude_response" | jq '.[] | select(.type == "result") | .structured_output // empty' 2>/dev/null
}
