#!/bin/bash
# judge.sh - Claude-based continuation evaluation
#
# Calls a separate Claude instance to judge whether the assistant
# has more autonomous work to do.

# === Exported Prompt/Schema Definitions (used by both production and snapshot extraction) ===
# v2 schema: extends v1 with confidence, decision_category, signals, risk_level
JUDGE_JSON_SCHEMA='{"type":"object","properties":{"should_continue":{"type":"boolean","description":"Primary decision: should work continue?"},"reasoning":{"type":"string","description":"Full explanation of the decision"},"reasons":{"type":"array","items":{"type":"string"},"description":"Structured list of reasons for logging/analysis"},"confidence":{"type":"number","minimum":0,"maximum":1,"description":"Confidence in decision (0=uncertain, 1=very certain)"},"decision_category":{"type":"string","enum":["explicit_continuation","task_completion","waiting_for_user","blocker","incomplete_work","uncertain"],"description":"Why decision was made"},"signals":{"type":"array","items":{"type":"string","enum":["explicit_next_steps","explicit_completion","asking_for_approval","asking_for_decision","asking_for_clarification","offering_optional_work","incomplete_implementation","error_blocking_progress","missing_information","mid_task_question","stated_todo_items","offering_continuation_question"]},"description":"Detected signal types from transcript"},"risk_level":{"type":"string","enum":["low","medium","high"],"description":"Risk of continuing (high=edge case, low=safe)"},"next_action":{"type":"string","description":"What the assistant should do next (if should_continue=true)"},"constraints":{"type":"array","items":{"type":"string"},"description":"Any constraints or blockers affecting decision"}},"required":["should_continue","reasoning"]}'

JUDGE_SYSTEM_PROMPT="You are a conversation state classifier. Your only job is to analyze conversation transcripts and determine if the assistant has more autonomous work to do. You output structured JSON with decision metadata including confidence scores, categorization, and detected signals. You do not write code or use tools."

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

ADDITIONALLY, provide these v2 metadata fields:

confidence (0.0-1.0): How certain are you?
- 0.9-1.0: Very clear signals (explicit "Next I'll..." or clear completion)
- 0.7-0.9: Strong indicators but some ambiguity
- 0.5-0.7: Uncertain, could go either way
- <0.5: Very uncertain, defaulting to safe choice

decision_category: Which best describes the situation?
- explicit_continuation: Clear statement of next steps
- task_completion: Work is done, no more to do
- waiting_for_user: Needs user input/decision/approval
- blocker: Cannot proceed (errors, missing info)
- incomplete_work: Unfinished but no explicit next step
- uncertain: Cannot confidently categorize

signals: Which signals did you detect? (array, pick all that apply)
- explicit_next_steps: "Next I'll...", "Now I need to..."
- explicit_completion: "Done", "Complete", "Finished"
- asking_for_approval: Waiting for user confirmation
- asking_for_decision: "Which approach...?", "Should we...?"
- asking_for_clarification: Needs more information
- offering_optional_work: "Want me to also...?"
- incomplete_implementation: Stated todos not yet done
- error_blocking_progress: Errors preventing continuation
- missing_information: Can't proceed without user input
- mid_task_question: "Should I continue?" during active work
- stated_todo_items: Pending items in a list
- offering_continuation_question: Permission-seeking ("Ready to proceed?")

risk_level: How risky is this decision?
- low: Clear signals, high confidence
- medium: Some ambiguity but reasonable choice
- high: Edge case, could easily be wrong

reasons: List the key factors that led to your decision (array of strings)
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

# === Heuristic Signal Prefilter (Phase 3) ===
# Detects clear stop/continue signals via pattern matching
# Runs AFTER Phase 1 permission language check
# Returns signal type or empty string if no match

# Detect heuristic signals from recent context
# Args: recent_context (JSON array via stdin or $1)
# Returns: signal type (asking_for_clarification, missing_information, explicit_next_steps, stated_todo_items) or empty
detect_heuristic_signal() {
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

    # === STOP signals (approve stop without judge) ===

    # asking_for_clarification - requires question mark
    # Patterns: "clarify", "can you explain", "what should", "how should"
    if grep -q '\?' <<< "$last_assistant"; then
        if grep -Eqi "(can you (clarify|explain)|clarify.*\?|what (should|would you like)|how should)" <<< "$last_assistant"; then
            echo "asking_for_clarification"
            return 0
        fi
    fi

    # missing_information - NO question mark required
    # Patterns: credential/API key/password requests with tight proximity, "I can't proceed without"
    # Note: avoid false positive on "password strength" or "token validation" mentions
    if grep -Eqi "(need.{0,15}(credential|api.?key|the password|the token|the secret)|provide.{0,15}(credential|api.?key|password|token)|can'?t proceed without|where (is|are) the.{0,10}(credential|key|password|token|secret))" <<< "$last_assistant"; then
        echo "missing_information"
        return 0
    fi

    # === CONTINUE signals (block stop without judge) ===
    # NO question mark required

    # explicit_next_steps - clear statement of what comes next
    # Patterns: "Next I", "Then I'll", "Now I need to", "Moving on to", "Let me"
    if grep -Eqi "(next i('ll| will| need| am going)|then i('ll| will)|now i('ll| will| need)|moving on to|let me (now |start |begin |continue ))" <<< "$last_assistant"; then
        echo "explicit_next_steps"
        return 0
    fi

    # stated_todo_items - list with pending/uncompleted items
    # Look for numbered/bulleted list patterns with pending markers
    if echo "$last_assistant" | grep -Eq "^[[:space:]]*([0-9]+\.|[-*•])[[:space:]]" 2>/dev/null; then
        # Check if list has uncompleted items (pending, todo, need, remaining, not yet, next)
        if grep -Eqi "(pending|todo|need to|remaining|not yet|next:|upcoming)" <<< "$last_assistant"; then
            echo "stated_todo_items"
            return 0
        fi
    fi

    # No clear signal - fall through to judge
    return 1
}

# Map heuristic signal to stop decision
# Args: signal type
# Returns: "true" (stop/approve), "false" (continue/block), or empty (unknown)
heuristic_should_stop() {
    local signal="$1"

    case "$signal" in
        asking_for_clarification|missing_information)
            # User input needed → STOP (approve)
            echo "true"
            ;;
        explicit_next_steps|stated_todo_items)
            # Work continues → CONTINUE (block)
            echo "false"
            ;;
        *)
            # Unknown signal → fall back to judge
            echo ""
            ;;
    esac
}

# Build v2 evaluation payload for heuristic decisions
# Args: signal, should_stop (true/false), decision (block/approve)
# Returns: JSON string with v2 metadata
build_heuristic_evaluation() {
    local signal="$1"
    local should_stop="$2"
    local decision="$3"

    local decision_category
    local should_continue

    if [ "$should_stop" = "true" ]; then
        should_continue="false"
        case "$signal" in
            asking_for_clarification)
                decision_category="waiting_for_user"
                ;;
            missing_information)
                decision_category="blocker"
                ;;
            *)
                decision_category="waiting_for_user"
                ;;
        esac
    else
        should_continue="true"
        decision_category="explicit_continuation"
    fi

    # Build JSON with jq
    jq -nc \
        --argjson should_continue "$should_continue" \
        --arg reasoning "Heuristic detected signal '$signal' - $decision without judge" \
        --arg decision_category "$decision_category" \
        --arg signal "$signal" \
        --arg risk_level "low" \
        '{
            should_continue: $should_continue,
            reasoning: $reasoning,
            decision_category: $decision_category,
            signals: [$signal],
            risk_level: $risk_level,
            reasons: ["heuristic:\($signal)"]
        }'
}
