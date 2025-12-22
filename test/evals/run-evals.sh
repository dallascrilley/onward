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

echo "🔒 Snapshot Test"
"$SNAPSHOT_TEST_SCRIPT"
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

# Process each scenario file
for scenario_file in "$SCENARIOS_DIR"/$SCENARIO_GLOB; do
    if [ ! -f "$scenario_file" ]; then
        continue
    fi

    total_scenarios=$((total_scenarios + 1))
    scenario_name=$(jq -r '.name' "$scenario_file")
    description=$(jq -r '.description' "$scenario_file")
    expected_decision=$(jq -r '.expected_decision' "$scenario_file")

    echo "📝 Scenario: $scenario_name"
    echo "   Description: $description"
    echo "   Expected: should_continue = $expected_decision"
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
            hook_output=$(echo "$hook_event" | STUB_EXPECTED_DECISION="$expected_decision" "$HOOK_SCRIPT" 2>"$stderr_file")
        else
            hook_output=$(echo "$hook_event" | "$HOOK_SCRIPT" 2>"$stderr_file")
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

        # Check if it matches expected
        if [ "$hook_should_continue" = "$expected_decision" ]; then
            passes=$((passes + 1))
            echo -e "   ${GREEN}✓${NC} Run $run: PASS (decision: $decision)"
        else
            fails=$((fails + 1))
            echo -e "   ${RED}✗${NC} Run $run: FAIL (decision: $decision, expected should_continue: $expected_decision)"
            echo "      Reason: $reason"
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

if [ $total_failed -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 All scenarios passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some scenarios failed${NC}"
    exit 1
fi
