#!/bin/bash

# Hook Evaluation Test Suite
# Runs contrived conversation scenarios through the hook and validates decisions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"
HOOK_SCRIPT="$SCRIPT_DIR/../../hooks/claude-judge-continuation.sh"
TEMP_DIR="/tmp/hook-evals-$$"

# Configuration with environment variable overrides
EVAL_PROVIDER=${EVAL_PROVIDER:-stub}
RUNS_PER_SCENARIO=${RUNS_PER_SCENARIO:-5}
SCENARIO_GLOB=${SCENARIO_GLOB:-*.json}

# Inject stub claude binary into PATH for fast testing (default)
if [ "$EVAL_PROVIDER" = "stub" ]; then
    export PATH="$SCRIPT_DIR/bin:$PATH"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate hook script exists and is executable
if [ ! -x "$HOOK_SCRIPT" ]; then
    echo -e "${RED}ERROR: Hook script not found or not executable: $HOOK_SCRIPT${NC}" >&2
    exit 1
fi

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

for scenario_file in "$SCENARIOS_DIR"/$SCENARIO_GLOB; do
    [ ! -f "$scenario_file" ] && continue

    if ! validation_errors=$(validate_scenario "$scenario_file"); then
        echo -e "${RED}INVALID:${NC} $(basename "$scenario_file")"
        echo "$validation_errors" | sed 's/^/  - /'
        validation_failed=true
    fi
done

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

    # Run the scenario 5 times
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

        # Run the hook script (pass expected_decision for stub mode)
        hook_output=$(echo "$hook_event" | STUB_EXPECTED_DECISION="$expected_decision" "$HOOK_SCRIPT" 2>&1)
        hook_exit_code=$?
        if [ $hook_exit_code -ne 0 ]; then
            echo -e "   ${RED}✗${NC} Run $run: HOOK EXECUTION FAILED (exit code: $hook_exit_code)"
            echo "      Output: $hook_output"
            fails=$((fails + 1))
            continue
        fi

        # Validate JSON response
        if ! echo "$hook_output" | jq -e '.decision' >/dev/null 2>&1; then
            echo -e "   ${RED}✗${NC} Run $run: INVALID HOOK RESPONSE (not valid JSON with decision)"
            echo "      Output: $hook_output"
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
