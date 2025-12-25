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
#
# Signal priority (first match wins):
#   STOP signals:
#   1. asking_for_approval (stop)
#   2. asking_for_decision (stop)
#   3. offering_optional_work (stop)
#   4. asking_for_clarification (stop)
#   5. missing_information (stop)
#   6. explicit_completion (stop)
#   7. uncertain_completion (stop)
#   8. handoff_to_user (stop)
#   CONTINUE signals:
#   9. explicit_next_steps (continue)
#   10. stated_todo_items (continue)
#   11. error_recovery (continue)
#   12. transition_phrase (continue)
#   13. verification_intent (continue)

# Detect heuristic signals from recent context
# Args: recent_context (JSON array via stdin or $1)
# Returns: signal type or empty
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

    local has_explicit_next_steps=false
    if grep -Eqi "(next i('ll| will| need| am going)|then i('ll| will)|now i('ll| will| need)|moving on to|let me (now |start |begin |continue ))" <<< "$last_assistant"; then
        has_explicit_next_steps=true
    fi

    # === STOP signals (approve stop without judge) ===

    if grep -q '\?' <<< "$last_assistant"; then
        # asking_for_approval - requires question mark
        # Patterns: "does this look/seem/sound/work", "is this ok/correct"
        if grep -Eqi "(does (this|that).*(look|seem|sound|work|make sense)|is (this|that).*(ok|okay|correct|right|good))" <<< "$last_assistant"; then
            echo "asking_for_approval"
            return 0
        fi

        # asking_for_decision - requires question mark
        # Patterns: "which", "choose", "prefer", "option ... or"
        if grep -Eqi "(which|choose|prefer|option.*or)" <<< "$last_assistant"; then
            echo "asking_for_decision"
            return 0
        fi

        # offering_optional_work - requires question mark
        # Patterns: "want me to", "should I also", "optional", "nice-to-have"
        if [ "$has_explicit_next_steps" != "true" ] && grep -Eqi "(want me to|should i also|should i add|optional|nice[- ]?to[- ]?have)" <<< "$last_assistant"; then
            echo "offering_optional_work"
            return 0
        fi

        # asking_for_clarification - requires question mark
        # Patterns: "clarify", "can you explain", "what should", "how should"
        if grep -Eqi "(can you (clarify|explain)|clarify.*\?|what (should|would you like)|how should)" <<< "$last_assistant"; then
            echo "asking_for_clarification"
            return 0
        fi
    fi

    # missing_information - NO question mark required
    # Patterns: explicit need/provide/blocked phrasing with credentials/keys
    # Use [[:<:]] and [[:>:]] for POSIX/BSD word boundaries (macOS compatible)
    if grep -Eqi "([[:<:]]need[[:>:]].{0,15}(credential|api.?key|the password|the token|the secret)|[[:<:]]provide[[:>:]].{0,15}(credential|api.?key|password|token|secret)|can'?t proceed without.{0,10}(credential|key|password|token|secret)|[[:<:]]where[[:>:]][[:space:]]+(is|are)[[:space:]]+the.{0,10}(credential|key|password|token|secret))" <<< "$last_assistant"; then
        echo "missing_information"
        return 0
    fi

    # explicit_completion - NO question mark required
    # Patterns: clear completion statements at sentence boundaries
    if grep -Eqi "(^|[.!] )(done|complete|finished|all set|ready to use|verified and working|is now (ready|live|deployed))[.!]" <<< "$last_assistant"; then
        echo "explicit_completion"
        return 0
    fi

    # uncertain_completion - NO question mark required
    # Patterns: hedged completion language
    if grep -Eqi "(that should (work|fix)|should be (fixed|working|good)|i think (that's (all|everything)|we're done))" <<< "$last_assistant"; then
        echo "uncertain_completion"
        return 0
    fi

    # handoff_to_user - NO question mark required
    # Patterns: handing control back to user
    if grep -Eqi "(you can now|ready for (your review|you to)|setup (is )?complete|is ready for)" <<< "$last_assistant"; then
        echo "handoff_to_user"
        return 0
    fi

    # === CONTINUE signals (block stop without judge) ===
    # NO question mark required

    # explicit_next_steps - clear statement of what comes next
    # Patterns: "Next I", "Then I'll", "Now I need to", "Moving on to", "Let me"
    if [ "$has_explicit_next_steps" = "true" ]; then
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

    # error_recovery - errors/failures requiring fix (but not success statements)
    # Patterns: explicit error indicators, excluding "no errors" success contexts
    local has_error_pattern=false
    local is_success_context=false
    if grep -Eqi "(failed with|build failed|tests? (are )?failing|[0-9]+ (type )?errors?)" <<< "$last_assistant"; then
        has_error_pattern=true
    fi
    if grep -Eqi "(no (type )?errors|passes with no|without (any )?errors|0 errors)" <<< "$last_assistant"; then
        is_success_context=true
    fi
    if [ "$has_error_pattern" = "true" ] && [ "$is_success_context" = "false" ]; then
        echo "error_recovery"
        return 0
    fi

    # transition_phrase - almost done with explicit remaining work
    # Patterns: transition words with stated remaining items
    if grep -Eqi "(almost done.*(just|need|still)|one more (thing|step)|just need to)" <<< "$last_assistant"; then
        echo "transition_phrase"
        return 0
    fi

    # verification_intent - about to verify/check/test
    # Patterns: stated intent to verify before completion
    if grep -Eqi "(let me (verify|check|test|confirm)|i'll (verify|check|test)|going to (verify|test|check))" <<< "$last_assistant"; then
        echo "verification_intent"
        return 0
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
        asking_for_approval|asking_for_decision|offering_optional_work|asking_for_clarification|missing_information|explicit_completion|uncertain_completion|handoff_to_user)
            # User input needed or work complete → STOP (approve)
            echo "true"
            ;;
        explicit_next_steps|stated_todo_items|error_recovery|transition_phrase|verification_intent)
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
    local should_continue_bool

    if [ "$should_stop" = "true" ]; then
        should_continue_bool=false
        case "$signal" in
            missing_information)
                decision_category="blocker"
                ;;
            explicit_completion|uncertain_completion|handoff_to_user)
                decision_category="task_completion"
                ;;
            *)
                decision_category="waiting_for_user"
                ;;
        esac
    else
        should_continue_bool=true
        # All CONTINUE signals indicate explicit continuation intent
        decision_category="explicit_continuation"
    fi

    # Build JSON with jq (use unquoted boolean for --argjson)
    jq -nc \
        --argjson should_continue "$should_continue_bool" \
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

# === Stall Detection (Phase 5) ===
# Detects non-progress loops via context fingerprinting and trend analysis
# Runs after heuristic check, before judge call

# Detect stall signals from decision history
# Args: current_context_hash, decision_log_file
# Returns: JSON object with signal flags (context_unchanged, confidence_declining, same_category_repeated) or empty string
detect_stall() {
    local current_context_hash="$1"
    local decision_log_file="$2"

    # No log file or hash → no stall detection
    [ -n "$current_context_hash" ] || return 1
    [ -f "$decision_log_file" ] || return 1

    local last_decisions
    last_decisions=$(tail -n 10 "$decision_log_file" 2>/dev/null)
    [ -n "$last_decisions" ] || return 1

    # Initialize signal flags
    local context_unchanged=0
    local confidence_declining=0
    local same_category_repeated=0
    local category_repeat_count=0

    # Check 1: Context hash unchanged across entries
    local prev_hashes
    prev_hashes=$(echo "$last_decisions" | jq -r '.context_hash // empty' 2>/dev/null | grep -v '^$')
    if [ -n "$prev_hashes" ]; then
        local unchanged_count=0
        while IFS= read -r hash; do
            [ "$hash" = "$current_context_hash" ] && ((unchanged_count++))
        done <<< "$prev_hashes"
        # If 2+ previous decisions had same hash as current → stall
        if [ "$unchanged_count" -ge 2 ]; then
            context_unchanged=1
        fi
    fi

    # Check 2: Confidence trend declining (3+ decisions with decreasing values)
    local confidences
    confidences=$(echo "$last_decisions" | jq -r '.evaluation.confidence // empty' 2>/dev/null | grep -v '^$' | tail -3)
    if [ "$(echo "$confidences" | wc -l | tr -d ' ')" -ge 3 ]; then
        local prev_conf=999
        local declining=true
        while IFS= read -r conf; do
            # Compare using bc for float comparison
            if command -v bc >/dev/null 2>&1; then
                if [ "$(echo "$conf >= $prev_conf" | bc -l 2>/dev/null)" = "1" ]; then
                    declining=false
                    break
                fi
            else
                # Fallback: skip decimal comparison without bc
                declining=false
                break
            fi
            prev_conf="$conf"
        done <<< "$confidences"
        if [ "$declining" = "true" ]; then
            confidence_declining=1
        fi
    fi

    local categories
    categories=$(echo "$last_decisions" | jq -r '.evaluation.decision_category // empty' 2>/dev/null | grep -v '^$')
    if [ -n "$categories" ]; then
        local consecutive_count=0
        local prev_category=""
        while IFS= read -r category; do
            if [ -n "$category" ]; then
                if [ "$category" = "$prev_category" ]; then
                    ((consecutive_count++))
                else
                    consecutive_count=1
                    prev_category="$category"
                fi
                if [ "$consecutive_count" -ge 3 ]; then
                    same_category_repeated=1
                    category_repeat_count="$consecutive_count"
                    break
                fi
            fi
        done <<< "$categories"
    fi

    if [ "$context_unchanged" = "1" ] || [ "$confidence_declining" = "1" ] || [ "$same_category_repeated" = "1" ]; then
        jq -nc \
            --argjson context_unchanged "$context_unchanged" \
            --argjson confidence_declining "$confidence_declining" \
            --argjson same_category_repeated "$same_category_repeated" \
            --argjson category_repeat_count "${category_repeat_count:-0}" \
            '{
                context_unchanged: $context_unchanged,
                confidence_declining: $confidence_declining,
                same_category_repeated: $same_category_repeated,
                category_repeat_count: $category_repeat_count
            }'
        return 0
    fi

    return 1
}

# Calculate stall risk score 0-100
# Args: context_unchanged (0/1), confidence_declining (0/1), category_repeat_count, throttle_count
# Returns: risk score 0-100
calculate_stall_risk() {
    local context_unchanged="${1:-0}"
    local confidence_declining="${2:-0}"
    local category_repeat_count="${3:-0}"
    local throttle_count="${4:-0}"

    local risk=0

    # Context unchanged: 30 points
    [ "$context_unchanged" = "1" ] && ((risk += 30))

    # Confidence declining: 20 points
    [ "$confidence_declining" = "1" ] && ((risk += 20))

    # Category repeated 3+: 20 points
    [ "$category_repeat_count" -ge 3 ] && ((risk += 20))

    # Throttle count: 15 points per continuation
    ((risk += throttle_count * 15))

    # Cap at 100
    [ "$risk" -gt 100 ] && risk=100

    echo "$risk"
}
