#!/bin/bash

# Hook Evaluation Test Suite
# Runs contrived conversation scenarios through the hook and validates decisions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"
# Canonical hook script path for testing (relative to repo root: hooks/claude-judge-continuation.sh)
# Note: The hook system uses ${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd as entrypoint,
# but tests call the script directly for validation.
HOOK_SCRIPT="$SCRIPT_DIR/../../hooks/claude-judge-continuation.sh"
TEMP_DIR="/tmp/hook-evals-$$"
SNAPSHOT_TEST_SCRIPT="$SCRIPT_DIR/../test-snapshot.sh"
PROMPT_DOD_TEST_SCRIPT="$SCRIPT_DIR/../test-dod-prompt.sh"
EXPLAIN_DOD_TEST_SCRIPT="$SCRIPT_DIR/../test-explain-dod.sh"

# Configuration with environment variable overrides
EVAL_OFFLINE=${EVAL_OFFLINE:-1}
RUNS_PER_SCENARIO=${RUNS_PER_SCENARIO:-5}
SCENARIO_GLOB=${SCENARIO_GLOB:-*.json}

# Inject stub claude binary into PATH for deterministic offline testing (opt-in)
if [ "$EVAL_OFFLINE" = "1" ]; then
    echo "OFFLINE MODE: Using stub claude binary (deterministic, no network)" >&2
    export PATH="$SCRIPT_DIR/bin:$PATH"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# === v2 Field Validation Functions ===

# Generate stub-compatible v2 fields from expected_v2_fields constraints
# Returns JSON that the stub can use to produce valid v2 output
generate_stub_v2_fields() {
    local expected_v2="$1"
    local expected_decision="$2"

    # If no expected_v2_fields, return empty (stub uses defaults)
    [ -z "$expected_v2" ] || [ "$expected_v2" = "null" ] && return 0

    local confidence category risk signals

    # Confidence: use midpoint of range, or min+0.05, or explicit value
    local conf_min conf_max
    conf_min=$(echo "$expected_v2" | jq -r '.confidence_min // empty')
    conf_max=$(echo "$expected_v2" | jq -r '.confidence_max // empty')
    if [ -n "$conf_min" ] && [ -n "$conf_max" ]; then
        # Use midpoint
        confidence=$(echo "scale=2; ($conf_min + $conf_max) / 2" | bc)
    elif [ -n "$conf_min" ]; then
        confidence=$(echo "scale=2; $conf_min + 0.05" | bc)
    elif [ -n "$conf_max" ]; then
        confidence=$(echo "scale=2; $conf_max - 0.05" | bc)
    fi

    # Category: use exact match or first of any-of list
    category=$(echo "$expected_v2" | jq -r '.decision_category // empty')
    if [ -z "$category" ]; then
        category=$(echo "$expected_v2" | jq -r '.decision_category_any[0] // empty')
    fi

    # Risk: use exact match or first of any-of list
    risk=$(echo "$expected_v2" | jq -r '.risk_level // empty')
    if [ -z "$risk" ]; then
        risk=$(echo "$expected_v2" | jq -r '.risk_level_any[0] // empty')
    fi

    # Signals: use signals_include or generate from signals_length_min
    local signals_include
    signals_include=$(echo "$expected_v2" | jq -c '.signals_include // empty')
    if [ -n "$signals_include" ] && [ "$signals_include" != "null" ] && [ "$signals_include" != "" ]; then
        signals="$signals_include"
    fi

    # Build the stub v2 fields JSON
    local result="{}"
    [ -n "$confidence" ] && result=$(echo "$result" | jq --argjson c "$confidence" '. + {confidence: $c}')
    [ -n "$category" ] && result=$(echo "$result" | jq --arg c "$category" '. + {decision_category: $c}')
    [ -n "$risk" ] && result=$(echo "$result" | jq --arg r "$risk" '. + {risk_level: $r}')
    [ -n "$signals" ] && [ "$signals" != "null" ] && result=$(echo "$result" | jq --argjson s "$signals" '. + {signals: $s}')

    echo "$result"
}

# Validate v2 fields from last_decision.json against expected_v2_fields
# Returns: 0 if valid, 1 if invalid (with error message on stdout)
validate_v2_fields() {
    local decision_file="$1"
    local expected_v2="$2"
    local errors=""

    # If no expected_v2_fields, skip validation
    [ -z "$expected_v2" ] || [ "$expected_v2" = "null" ] && return 0

    # Read evaluation from decision file
    local evaluation
    evaluation=$(jq -r '.evaluation // empty' "$decision_file" 2>/dev/null)
    [ -z "$evaluation" ] && { echo "v2: no evaluation in decision file"; return 1; }

    # Validate confidence range
    local conf_min conf_max actual_conf
    conf_min=$(echo "$expected_v2" | jq -r '.confidence_min // empty')
    conf_max=$(echo "$expected_v2" | jq -r '.confidence_max // empty')
    actual_conf=$(echo "$evaluation" | jq -r '.confidence // empty')

    if [ -n "$conf_min" ] && [ -n "$actual_conf" ]; then
        if [ "$(echo "$actual_conf < $conf_min" | bc)" -eq 1 ]; then
            errors="$errors confidence $actual_conf < min $conf_min;"
        fi
    fi
    if [ -n "$conf_max" ] && [ -n "$actual_conf" ]; then
        if [ "$(echo "$actual_conf > $conf_max" | bc)" -eq 1 ]; then
            errors="$errors confidence $actual_conf > max $conf_max;"
        fi
    fi

    # Validate decision_category (exact or any-of)
    local expected_cat expected_cat_any actual_cat
    expected_cat=$(echo "$expected_v2" | jq -r '.decision_category // empty')
    expected_cat_any=$(echo "$expected_v2" | jq -c '.decision_category_any // empty')
    actual_cat=$(echo "$evaluation" | jq -r '.decision_category // empty')

    if [ -n "$expected_cat" ] && [ -n "$actual_cat" ]; then
        if [ "$actual_cat" != "$expected_cat" ]; then
            errors="$errors category '$actual_cat' != '$expected_cat';"
        fi
    elif [ -n "$expected_cat_any" ] && [ "$expected_cat_any" != "null" ] && [ -n "$actual_cat" ]; then
        if ! echo "$expected_cat_any" | jq -e --arg c "$actual_cat" 'index($c) != null' > /dev/null; then
            errors="$errors category '$actual_cat' not in $expected_cat_any;"
        fi
    fi

    # Validate risk_level (exact or any-of)
    local expected_risk expected_risk_any actual_risk
    expected_risk=$(echo "$expected_v2" | jq -r '.risk_level // empty')
    expected_risk_any=$(echo "$expected_v2" | jq -c '.risk_level_any // empty')
    actual_risk=$(echo "$evaluation" | jq -r '.risk_level // empty')

    if [ -n "$expected_risk" ] && [ -n "$actual_risk" ]; then
        if [ "$actual_risk" != "$expected_risk" ]; then
            errors="$errors risk '$actual_risk' != '$expected_risk';"
        fi
    elif [ -n "$expected_risk_any" ] && [ "$expected_risk_any" != "null" ] && [ -n "$actual_risk" ]; then
        if ! echo "$expected_risk_any" | jq -e --arg r "$actual_risk" 'index($r) != null' > /dev/null; then
            errors="$errors risk '$actual_risk' not in $expected_risk_any;"
        fi
    fi

    # Validate signals_include (all must be present)
    local signals_include actual_signals
    signals_include=$(echo "$expected_v2" | jq -c '.signals_include // empty')
    actual_signals=$(echo "$evaluation" | jq -c '.signals // []')

    if [ -n "$signals_include" ] && [ "$signals_include" != "null" ] && [ "$signals_include" != "" ]; then
        for sig in $(echo "$signals_include" | jq -r '.[]'); do
            if ! echo "$actual_signals" | jq -e --arg s "$sig" 'index($s) != null' > /dev/null; then
                errors="$errors signal '$sig' missing from $actual_signals;"
            fi
        done
    fi

    # Validate signals_length_min
    local signals_len_min actual_len
    signals_len_min=$(echo "$expected_v2" | jq -r '.signals_length_min // empty')
    if [ -n "$signals_len_min" ]; then
        actual_len=$(echo "$actual_signals" | jq 'length')
        if [ "$actual_len" -lt "$signals_len_min" ]; then
            errors="$errors signals count $actual_len < min $signals_len_min;"
        fi
    fi

    if [ -n "$errors" ]; then
        echo "v2:$errors"
        return 1
    fi
    return 0
}

# === End v2 Functions ===

# Validate run configuration before using it
validate_run_config() {
    # Ensure RUNS_PER_SCENARIO is numeric
    if ! [[ "$RUNS_PER_SCENARIO" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}ERROR: RUNS_PER_SCENARIO must be a positive integer, got '${RUNS_PER_SCENARIO}'.${NC}" >&2
        exit 1
    fi

    # Ensure RUNS_PER_SCENARIO is at least 1
    if [ "$RUNS_PER_SCENARIO" -lt 1 ]; then
        echo -e "${RED}ERROR: RUNS_PER_SCENARIO must be at least 1, got '${RUNS_PER_SCENARIO}'.${NC}" >&2
        exit 1
    fi
}

validate_run_config

# Validate hook script exists and is executable
if [ ! -x "$HOOK_SCRIPT" ]; then
    echo -e "${RED}ERROR: Hook script not found or not executable: $HOOK_SCRIPT${NC}" >&2
    exit 1
fi

# Snapshot guard: ensure prompt/schema drift is intentional
if [ ! -x "$SNAPSHOT_TEST_SCRIPT" ]; then
    echo -e "${RED}ERROR: Snapshot test script not found or not executable: $SNAPSHOT_TEST_SCRIPT${NC}" >&2
    exit 1
fi
if [ ! -x "$PROMPT_DOD_TEST_SCRIPT" ]; then
    echo -e "${RED}ERROR: DoD prompt test script not found or not executable: $PROMPT_DOD_TEST_SCRIPT${NC}" >&2
    exit 1
fi
if [ ! -x "$EXPLAIN_DOD_TEST_SCRIPT" ]; then
    echo -e "${RED}ERROR: DoD explain test script not found or not executable: $EXPLAIN_DOD_TEST_SCRIPT${NC}" >&2
    exit 1
fi

echo "🔒 Snapshot Test"
"$SNAPSHOT_TEST_SCRIPT"
echo ""

echo "🧾 DoD Prompt Test"
"$PROMPT_DOD_TEST_SCRIPT"
echo ""

echo "🧾 Explain DoD Test"
"$EXPLAIN_DOD_TEST_SCRIPT"
echo ""

# Cleanup on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR"

# Validate scenario JSON schema
validate_scenario() {
    local scenario_file="$1"
    local errors=()

    # Check file is valid JSON
    local jq_error
    if ! jq_error=$(jq empty "$scenario_file" 2>&1); then
        echo "Invalid JSON: $jq_error"
        return 1
    fi

    # Check required fields exist and have correct types
    local name=$(jq -r '.name // empty' "$scenario_file")
    local desc=$(jq -r '.description // empty' "$scenario_file")
    local has_decision=$(jq 'has("expected_decision")' "$scenario_file")
    local transcript_type=$(jq -r '.transcript | type' "$scenario_file")

    [ -z "$name" ] && errors+=("missing or empty 'name'")
    [ -z "$desc" ] && errors+=("missing or empty 'description'")

    # Validate expected_decision exists and is boolean
    if [ "$has_decision" != "true" ]; then
        errors+=("missing 'expected_decision'")
    else
        local decision_type=$(jq -r '.expected_decision | type' "$scenario_file")
        [ "$decision_type" != "boolean" ] && errors+=("'expected_decision' must be boolean, got $decision_type")
    fi

    # Validate transcript is non-empty array
    if [ "$transcript_type" != "array" ]; then
        errors+=("'transcript' must be array, got $transcript_type")
    else
        local transcript_len=$(jq '.transcript | length' "$scenario_file")
        if [ "$transcript_len" -eq 0 ]; then
            errors+=("'transcript' is empty")
        else
            # Only validate messages if transcript is a valid non-empty array
            local invalid_messages=$(jq -r '
                .transcript | to_entries[] |
                select(.value.role == null or .value.content == null) |
                "message[\(.key)]: missing " +
                (if .value.role == null then "role" else "" end) +
                (if .value.role == null and .value.content == null then " and " else "" end) +
                (if .value.content == null then "content" else "" end)
            ' "$scenario_file") || true

            [ -n "$invalid_messages" ] && errors+=("$invalid_messages")

            # Validate role values
            local invalid_roles=$(jq -r '
                .transcript | to_entries[] |
                select(.value.role != "user" and .value.role != "assistant") |
                "message[\(.key)]: invalid role \(.value.role | @json)"
            ' "$scenario_file") || true

            [ -n "$invalid_roles" ] && errors+=("$invalid_roles")
        fi
    fi

    if [ ${#errors[@]} -gt 0 ]; then
        printf '%s\n' "${errors[@]}"
        return 1
    fi

    return 0
}

# Preflight: Validate all scenarios before running
echo "Validating scenario schemas..."
validation_failed=false
matched_scenarios=0

for scenario_file in "$SCENARIOS_DIR"/$SCENARIO_GLOB; do
    [ ! -f "$scenario_file" ] && continue
    matched_scenarios=$((matched_scenarios + 1))

    if ! validation_errors=$(validate_scenario "$scenario_file"); then
        echo -e "${RED}INVALID:${NC} $(basename "$scenario_file")"
        echo "$validation_errors" | sed 's/^/  - /'
        validation_failed=true
    fi
done

if [ "$matched_scenarios" -eq 0 ]; then
    echo -e "${RED}ERROR: No scenarios matched SCENARIO_GLOB='$SCENARIO_GLOB' in $SCENARIOS_DIR.${NC}" >&2
    exit 1
fi

if [ "$validation_failed" = true ]; then
    echo ""
    echo -e "${RED}Schema validation failed. Fix scenarios before running evals.${NC}"
    exit 1
fi

echo -e "${GREEN}All scenarios valid.${NC}"
echo ""

echo "🧪 Running Hook Evaluation Suite"
echo "================================="
echo ""

total_scenarios=0
total_passed=0
total_failed=0

# === Metrics Collection ===
# Track decision paths for performance analysis
metric_prefilter_permission=0
metric_prefilter_heuristic=0
metric_judge_calls=0
metric_early_exit=0  # throttle, transcript error, etc.
metric_continue_decisions=0
metric_stop_decisions=0
start_time=$(date +%s)

# Extra validation cases for transcript file handling (not representable via scenario JSON)
run_transcript_validation_cases() {
    echo "🔍 Transcript Validation Cases"
    echo "================================="
    echo ""

    local validation_dir="$TEMP_DIR/transcript-validation"
    mkdir -p "$validation_dir"

    run_case() {
        local name="$1"
        local transcript_path="$2"
        local expected_decision="$3"
        local expected_reason="$4"
        local stub_expected="$5"

        echo "🧩 Case: $name"
        total_scenarios=$((total_scenarios + 1))

        local hook_event
        hook_event=$(jq -n \
            --arg transcript_path "$transcript_path" \
            '{
                "stop_hook_active": false,
                "transcript_path": $transcript_path,
                "session_id": "eval-test-session"
            }')

        local hook_output hook_stderr
        local stderr_file="$TEMP_DIR/stderr-$$-$RANDOM"
        hook_output=$(echo "$hook_event" | STUB_EXPECTED_DECISION="$stub_expected" "$HOOK_SCRIPT" 2>"$stderr_file")
        local hook_exit_code=$?
        hook_stderr=$(cat "$stderr_file" 2>/dev/null)
        rm -f "$stderr_file"
        if [ $hook_exit_code -ne 0 ]; then
            echo -e "   ${RED}✗${NC} HOOK EXECUTION FAILED (exit code: $hook_exit_code)"
            echo "      Output: $hook_output"
            [ -n "$hook_stderr" ] && echo "      Stderr: $hook_stderr"
            total_failed=$((total_failed + 1))
            echo ""
            return
        fi

        if ! echo "$hook_output" | jq -e '.decision' >/dev/null 2>&1; then
            echo -e "   ${RED}✗${NC} INVALID HOOK RESPONSE (not valid JSON with decision)"
            echo "      Output: $hook_output"
            [ -n "$hook_stderr" ] && echo "      Stderr: $hook_stderr"
            total_failed=$((total_failed + 1))
            echo ""
            return
        fi

        local decision reason hook_should_continue=false reason_ok=true
        decision=$(echo "$hook_output" | jq -r '.decision')
        reason=$(echo "$hook_output" | jq -r '.reason // "No reason provided"')

        if [ "$decision" = "block" ]; then
            hook_should_continue=true
        fi

        if [ -n "$expected_reason" ] && ! printf '%s' "$reason" | grep -Fq "$expected_reason"; then
            reason_ok=false
        fi

        if [ "$hook_should_continue" = "$expected_decision" ] && [ "$reason_ok" = true ]; then
            echo -e "   ${GREEN}✓${NC} PASS (decision: $decision)"
            total_passed=$((total_passed + 1))
        else
            echo -e "   ${RED}✗${NC} FAIL (decision: $decision, expected should_continue: $expected_decision)"
            echo "      Reason: $reason"
            if [ "$reason_ok" = false ]; then
                echo "      Expected reason to include: $expected_reason"
            fi
            total_failed=$((total_failed + 1))
        fi
        echo ""
    }

    local missing_path="$validation_dir/does-not-exist.json"
    local empty_file="$validation_dir/empty.json"
    local unreadable_file="$validation_dir/unreadable.json"
    local invalid_file="$validation_dir/invalid.json"
    local mixed_file="$validation_dir/mixed.json"

    : > "$empty_file"
    printf '%s\n' '{"role":"assistant","content":"ok"}' > "$unreadable_file"
    chmod 000 "$unreadable_file"
    printf '%s\n' 'not json' '}{' > "$invalid_file"
    printf '%s\n' '{"role":"assistant","content":"ok"}' '' '}{' '{"role":"user","content":"hi"}' > "$mixed_file"

    run_case "missing transcript path" "" false "No transcript path provided" "false"
    run_case "missing transcript file" "$missing_path" false "Transcript file not found" "false"
    run_case "unreadable transcript file" "$unreadable_file" false "Transcript file not readable" "false"
    chmod 600 "$unreadable_file"
    run_case "empty transcript file" "$empty_file" false "Transcript file is empty" "false"
    run_case "invalid NDJSON only" "$invalid_file" false "No valid transcript entries found" "false"
    run_case "mixed valid/invalid NDJSON" "$mixed_file" true "Stub: Expected continuation" "true"

    echo "---"
    echo ""
}

# Decision file location for v2 validation
LAST_DECISION_FILE="${REDBULL_STATE_DIR:-$HOME/.claude/redbull}/last_decision.json"

# Process each scenario file
for scenario_file in "$SCENARIOS_DIR"/$SCENARIO_GLOB; do
    if [ ! -f "$scenario_file" ]; then
        continue
    fi

    total_scenarios=$((total_scenarios + 1))
    scenario_name=$(jq -r '.name' "$scenario_file")
    description=$(jq -r '.description' "$scenario_file")
    expected_decision=$(jq -r '.expected_decision' "$scenario_file")
    expected_v2_fields=$(jq -c '.expected_v2_fields // null' "$scenario_file")
    expected_path=$(jq -r '.expected_path // empty' "$scenario_file")

    echo "📝 Scenario: $scenario_name"
    echo "   Description: $description"
    echo "   Expected: should_continue = $expected_decision"
    if [ -n "$expected_path" ]; then
        echo "   Expected path: $expected_path"
    fi
    echo ""

    # Run the scenario multiple times
    passes=0
    fails=0

    for run in $(seq 1 $RUNS_PER_SCENARIO); do
        # Create transcript file from scenario (NDJSON format - one message per line)
        transcript_file="$TEMP_DIR/transcript-$total_scenarios-$run.json"
        jq -c '.transcript[]' "$scenario_file" > "$transcript_file"

        # Create mock hook event
        hook_event=$(jq -n \
            --arg transcript_path "$transcript_file" \
            '{
                "stop_hook_active": false,
                "transcript_path": $transcript_path,
                "session_id": "eval-test-session"
            }')

        # Run the hook script (pass expected_decision only in offline/stub mode)
        # Capture stdout for JSON parsing, stderr separately for diagnostics
        hook_stderr=""
        stderr_file=$(mktemp "$TEMP_DIR/stderr.XXXXXX") || {
            echo -e "   ${RED}✗${NC} Run $run: FAILED (could not create temp file)"
            fails=$((fails + 1))
            continue
        }
        if [ "$EVAL_OFFLINE" = "1" ]; then
            # Generate stub v2 fields from expected_v2_fields constraints
            stub_v2_fields=""
            if [ -n "$expected_v2_fields" ] && [ "$expected_v2_fields" != "null" ]; then
                stub_v2_fields=$(generate_stub_v2_fields "$expected_v2_fields" "$expected_decision")
            fi
            hook_output=$(echo "$hook_event" | REDBULL_DEBUG=true STUB_EXPECTED_DECISION="$expected_decision" STUB_V2_FIELDS="$stub_v2_fields" "$HOOK_SCRIPT" 2>"$stderr_file")
        else
            hook_output=$(echo "$hook_event" | REDBULL_DEBUG=true "$HOOK_SCRIPT" 2>"$stderr_file")
        fi
        hook_exit_code=$?
        hook_stderr=$(cat "$stderr_file" 2>/dev/null)
        rm -f "$stderr_file"
        if [ $hook_exit_code -ne 0 ]; then
            echo -e "   ${RED}✗${NC} Run $run: HOOK EXECUTION FAILED (exit code: $hook_exit_code)"
            echo "      Output: $hook_output"
            [ -n "$hook_stderr" ] && echo "      Stderr: $hook_stderr"
            fails=$((fails + 1))
            continue
        fi

        # Validate JSON response
        if ! echo "$hook_output" | jq -e '.decision' >/dev/null 2>&1; then
            echo -e "   ${RED}✗${NC} Run $run: INVALID HOOK RESPONSE (not valid JSON with decision)"
            echo "      Output: $hook_output"
            [ -n "$hook_stderr" ] && echo "      Stderr: $hook_stderr"
            fails=$((fails + 1))
            continue
        fi

        # Parse the hook decision
        decision=$(echo "$hook_output" | jq -r '.decision')
        reason=$(echo "$hook_output" | jq -r '.reason // "No reason provided"')

        # Determine if hook would continue (block = continue, approve = stop)
        hook_should_continue=false
        if [ "$decision" = "block" ]; then
            hook_should_continue=true
        fi

        # Check expected path (if provided) and track metrics
        path_ok=true
        actual_path=""
        # Always extract actual path for metrics (even if not validating)
        actual_path=$(printf '%s\n' "$hook_stderr" | jq -Rr 'fromjson? | select(.event=="prefilter_path") | .path' 2>/dev/null | tail -1)

        # Track metrics by path (only on first run to avoid overcounting)
        if [ "$run" -eq 1 ]; then
            case "$actual_path" in
                permission) metric_prefilter_permission=$((metric_prefilter_permission + 1)) ;;
                heuristic) metric_prefilter_heuristic=$((metric_prefilter_heuristic + 1)) ;;
                judge) metric_judge_calls=$((metric_judge_calls + 1)) ;;
                *) metric_early_exit=$((metric_early_exit + 1)) ;;  # No path = early exit
            esac
            # Track decision type
            if [ "$decision" = "block" ]; then
                metric_continue_decisions=$((metric_continue_decisions + 1))
            else
                metric_stop_decisions=$((metric_stop_decisions + 1))
            fi
        fi

        if [ -n "$expected_path" ]; then
            if [ -z "$actual_path" ] || [ "$actual_path" != "$expected_path" ]; then
                path_ok=false
            fi
        fi

        # Check if it matches expected
        if [ "$hook_should_continue" = "$expected_decision" ] && [ "$path_ok" = true ]; then
            # Decision matches, now validate v2 fields if expected
            v2_error=""
            if [ -n "$expected_v2_fields" ] && [ "$expected_v2_fields" != "null" ] && [ -f "$LAST_DECISION_FILE" ]; then
                v2_error=$(validate_v2_fields "$LAST_DECISION_FILE" "$expected_v2_fields" 2>/dev/null) || true
            fi

            if [ -z "$v2_error" ]; then
                passes=$((passes + 1))
                echo -e "   ${GREEN}✓${NC} Run $run: PASS (decision: $decision)"
            else
                fails=$((fails + 1))
                echo -e "   ${YELLOW}⚠${NC} Run $run: v2 FAIL (decision correct, v2 invalid)"
                echo "      $v2_error"
            fi
        else
            fails=$((fails + 1))
            echo -e "   ${RED}✗${NC} Run $run: FAIL (decision: $decision, expected should_continue: $expected_decision)"
            echo "      Reason: $reason"
            if [ "$path_ok" = false ]; then
                echo "      Expected path: $expected_path, actual: ${actual_path:-missing}"
            fi
        fi
    done

    echo ""

    # Report scenario results
    if [ $fails -eq 0 ]; then
        echo -e "   ${GREEN}✓ Scenario PASSED${NC} ($RUNS_PER_SCENARIO/$RUNS_PER_SCENARIO runs correct)"
        total_passed=$((total_passed + 1))
    else
        echo -e "   ${RED}✗ Scenario FAILED${NC} ($passes/$RUNS_PER_SCENARIO runs correct)"
        total_failed=$((total_failed + 1))
    fi

    echo ""
    echo "---"
    echo ""
done

# Only run file/NDJSON guard cases in offline mode (avoids real model calls)
if [ "$EVAL_OFFLINE" = "1" ]; then
    run_transcript_validation_cases
fi

# Final summary
echo "================================="
echo "📊 Final Results"
echo "================================="
echo "Total scenarios: $total_scenarios"
echo -e "Passed: ${GREEN}$total_passed${NC}"
echo -e "Failed: ${RED}$total_failed${NC}"

# === Metrics Summary ===
end_time=$(date +%s)
duration=$((end_time - start_time))
accuracy=$(echo "scale=4; $total_passed / $total_scenarios" | bc 2>/dev/null || echo "0")

echo ""
echo "📈 Metrics"
echo "---------"
echo "Decision paths:"
echo "  Permission prefilter: $metric_prefilter_permission"
echo "  Heuristic prefilter:  $metric_prefilter_heuristic"
echo "  Judge calls:          $metric_judge_calls"
echo "  Early exit:           $metric_early_exit"
echo ""
echo "Decisions:"
echo "  Continue (block):     $metric_continue_decisions"
echo "  Stop (approve):       $metric_stop_decisions"
echo ""
echo "Duration: ${duration}s"

# Calculate prefilter efficiency
total_decisions=$((metric_prefilter_permission + metric_prefilter_heuristic + metric_judge_calls))
if [ "$total_decisions" -gt 0 ]; then
    prefilter_total=$((metric_prefilter_permission + metric_prefilter_heuristic))
    prefilter_pct=$(echo "scale=1; $prefilter_total * 100 / $total_decisions" | bc 2>/dev/null || echo "0")
    echo "Prefilter efficiency:   ${prefilter_pct}% of decisions avoided judge"
fi

# Emit metrics JSON to results directory (if writable)
RESULTS_DIR="$SCRIPT_DIR/results"
if [ -d "$RESULTS_DIR" ]; then
    BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    COMMIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    SAFE_BRANCH_NAME="${BRANCH_NAME//\//-}"
    METRICS_FILE="$RESULTS_DIR/metrics-${SAFE_BRANCH_NAME}-$(date +%Y%m%d-%H%M%S).json"

    jq -n \
        --arg branch "$BRANCH_NAME" \
        --arg commit "$COMMIT_SHA" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson total_scenarios "$total_scenarios" \
        --argjson passed "$total_passed" \
        --argjson failed "$total_failed" \
        --arg accuracy "$accuracy" \
        --argjson duration "$duration" \
        --argjson prefilter_permission "$metric_prefilter_permission" \
        --argjson prefilter_heuristic "$metric_prefilter_heuristic" \
        --argjson judge_calls "$metric_judge_calls" \
        --argjson early_exit "$metric_early_exit" \
        --argjson continue_decisions "$metric_continue_decisions" \
        --argjson stop_decisions "$metric_stop_decisions" \
        --arg offline_mode "$EVAL_OFFLINE" \
        '{
            branch: $branch,
            commit: $commit,
            timestamp: $timestamp,
            scenarios: {
                total: $total_scenarios,
                passed: $passed,
                failed: $failed,
                accuracy: ($accuracy | tonumber)
            },
            paths: {
                prefilter_permission: $prefilter_permission,
                prefilter_heuristic: $prefilter_heuristic,
                judge_calls: $judge_calls,
                early_exit: $early_exit
            },
            decisions: {
                continue: $continue_decisions,
                stop: $stop_decisions
            },
            duration_seconds: $duration,
            offline_mode: ($offline_mode == "1")
        }' > "$METRICS_FILE"

    echo ""
    echo "📁 Metrics saved: $METRICS_FILE"
fi

if [ $total_failed -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 All scenarios passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some scenarios failed${NC}"
    exit 1
fi
