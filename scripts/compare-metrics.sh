#!/bin/bash

# Compare Metrics Across Branches/Runs
# Usage: ./scripts/compare-metrics.sh [file1.json] [file2.json] ...
#        ./scripts/compare-metrics.sh --latest N
#
# Compares eval metrics from test/evals/results/*.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/../test/evals/results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [file1.json] [file2.json] ...

Compare evaluation metrics across branches or runs.

Options:
  --latest N           Compare the N most recent metrics files
  --all                Compare all metrics files in results directory
  -h, --help           Show this help message

Examples:
  $(basename "$0") --latest 3                    # Compare last 3 runs
  $(basename "$0") --all                         # Compare all runs
  $(basename "$0") metrics-main.json metrics-phase-3.json

Results Directory: $RESULTS_DIR
EOF
    exit 0
}

# Parse arguments
FILES=()
LATEST=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --latest)
            if [[ $# -lt 2 ]]; then
                echo "Error: --latest requires a numeric argument" >&2
                exit 1
            fi
            LATEST="$2"
            shift 2
            ;;
        --all)
            LATEST=999
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            FILES+=("$1")
            shift
            ;;
    esac
done

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

# Get files to compare
if [[ "$LATEST" -gt 0 ]]; then
    if [[ ! -d "$RESULTS_DIR" ]]; then
        echo "No results directory found: $RESULTS_DIR"
        echo "Run ./test/evals/run-evals.sh to generate metrics."
        exit 1
    fi
    mapfile -t FILES < <(ls -t "$RESULTS_DIR"/metrics-*.json 2>/dev/null | head -n "$LATEST" || true)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No metrics files to compare."
    echo "Use --help for usage information."
    exit 1
fi

if [[ ${#FILES[@]} -eq 1 ]]; then
    echo "Need at least 2 files to compare. Found: ${FILES[0]}"
    exit 1
fi

# Print header
printf "\n${BOLD}📊 Metrics Comparison${NC}\n"
printf "=====================\n\n"

# Build header row
printf "%-25s" "Metric"
for f in "${FILES[@]}"; do
    BRANCH=$(jq -r '.branch // "?"' "$f" 2>/dev/null | head -c 15)
    printf "%-18s" "$BRANCH"
done
printf "\n"

# Separator
printf "%-25s" "-------------------------"
for f in "${FILES[@]}"; do
    printf "%-18s" "-----------------"
done
printf "\n"

# Helper to print a metric row
print_row() {
    local label="$1"
    local jq_path="$2"
    local format="${3:-%s}"

    printf "%-25s" "$label"
    for f in "${FILES[@]}"; do
        val=$(jq -r "$jq_path // \"?\"" "$f" 2>/dev/null)
        # Handle placeholder "?" for numeric formats to avoid printf errors
        if [[ "$val" == "?" ]] || [[ -z "$val" ]]; then
            printf "%-18s" "?"
        else
            printf "%-18s" "$(printf "$format" "$val" 2>/dev/null || echo "$val")"
        fi
    done
    printf "\n"
}

# Print metrics
print_row "Scenarios" ".scenarios.total"
print_row "Passed" ".scenarios.passed"
print_row "Failed" ".scenarios.failed"
print_row "Accuracy" ".scenarios.accuracy" "%.4f"
printf "\n"

print_row "Permission prefilter" ".paths.prefilter_permission"
print_row "Heuristic prefilter" ".paths.prefilter_heuristic"
print_row "Judge calls" ".paths.judge_calls"
print_row "Early exit" ".paths.early_exit"
printf "\n"

print_row "Continue decisions" ".decisions.continue"
print_row "Stop decisions" ".decisions.stop"
printf "\n"

print_row "Duration (s)" ".duration_seconds"
print_row "Commit" ".commit"

# Calculate and show deltas if exactly 2 files
if [[ ${#FILES[@]} -eq 2 ]]; then
    printf "\n${BOLD}📈 Delta (${FILES[1]} → ${FILES[0]})${NC}\n"
    printf "============================================\n\n"

    OLD="${FILES[1]}"
    NEW="${FILES[0]}"

    calc_delta() {
        local path="$1"
        local old_val=$(jq -r "$path // 0" "$OLD" 2>/dev/null)
        local new_val=$(jq -r "$path // 0" "$NEW" 2>/dev/null)
        echo $((new_val - old_val))
    }

    format_delta() {
        local val="$1"
        if [[ "$val" -gt 0 ]]; then
            echo -e "${GREEN}+$val${NC}"
        elif [[ "$val" -lt 0 ]]; then
            echo -e "${RED}$val${NC}"
        else
            echo "0"
        fi
    }

    DELTA_PERM=$(calc_delta ".paths.prefilter_permission")
    DELTA_HEUR=$(calc_delta ".paths.prefilter_heuristic")
    DELTA_JUDGE=$(calc_delta ".paths.judge_calls")

    echo "Permission prefilter:  $(format_delta $DELTA_PERM)"
    echo "Heuristic prefilter:   $(format_delta $DELTA_HEUR)"
    echo "Judge calls:           $(format_delta $DELTA_JUDGE)"

    # Efficiency change
    OLD_TOTAL=$(jq -r '(.paths.prefilter_permission + .paths.prefilter_heuristic + .paths.judge_calls) // 1' "$OLD")
    NEW_TOTAL=$(jq -r '(.paths.prefilter_permission + .paths.prefilter_heuristic + .paths.judge_calls) // 1' "$NEW")
    OLD_PREFILTER=$(jq -r '(.paths.prefilter_permission + .paths.prefilter_heuristic) // 0' "$OLD")
    NEW_PREFILTER=$(jq -r '(.paths.prefilter_permission + .paths.prefilter_heuristic) // 0' "$NEW")

    OLD_EFF=$(echo "scale=1; $OLD_PREFILTER * 100 / $OLD_TOTAL" | bc 2>/dev/null || echo "0")
    NEW_EFF=$(echo "scale=1; $NEW_PREFILTER * 100 / $NEW_TOTAL" | bc 2>/dev/null || echo "0")

    echo ""
    echo "Prefilter efficiency:  ${OLD_EFF}% → ${NEW_EFF}%"
fi

printf "\n"
