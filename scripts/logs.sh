#!/bin/bash

# Decision Log Viewer - View and analyze hook decision history
# Usage: ./scripts/logs.sh [OPTIONS]
#
# Requires: REDBULL_LOG_DECISIONS=true to capture logs

set -euo pipefail

# Configuration
DECISION_DIR="${REDBULL_STATE_DIR:-$HOME/.claude/redbull}"
DECISION_LOG_FILE="$DECISION_DIR/decision_log.jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
LINES=20
FORMAT="pretty"
FILTER=""

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

View and analyze the redbull decision log.

Options:
  -n, --lines N        Show last N entries (default: 20)
  -j, --json           Output raw JSON (one per line)
  -s, --stats          Show aggregate statistics
  -f, --filter EXPR    Filter by jq expression (e.g., '.decision=="block"')
  -a, --all            Show all entries
  -h, --help           Show this help message

Examples:
  $(basename "$0")                    # Last 20 decisions, pretty format
  $(basename "$0") -n 50              # Last 50 decisions
  $(basename "$0") -s                 # Statistics only
  $(basename "$0") -f '.decision=="block"'  # Only continue decisions
  $(basename "$0") --json | jq ...    # Pipe to jq for custom analysis

Note: Decision logging is enabled by default (last 500 entries).
      To disable: REDBULL_LOG_DECISIONS=false

Log Location: $DECISION_LOG_FILE
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--lines)
            LINES="$2"
            shift 2
            ;;
        -j|--json)
            FORMAT="json"
            shift
            ;;
        -s|--stats)
            FORMAT="stats"
            shift
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        -a|--all)
            LINES=0
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

# Check if log file exists
if [[ ! -f "$DECISION_LOG_FILE" ]]; then
    echo "No decision log found at: $DECISION_LOG_FILE"
    echo ""
    echo "Decision logging is enabled by default. The log will be created"
    echo "after the first hook decision is made."
    echo ""
    echo "To disable logging, set: REDBULL_LOG_DECISIONS=false"
    exit 0
fi

# Read log entries
if [[ "$LINES" -eq 0 ]]; then
    LOG_ENTRIES=$(cat "$DECISION_LOG_FILE")
else
    LOG_ENTRIES=$(tail -n "$LINES" "$DECISION_LOG_FILE")
fi

# Apply filter if provided
if [[ -n "$FILTER" ]]; then
    LOG_ENTRIES=$(echo "$LOG_ENTRIES" | jq -c 'select('"$FILTER"')' 2>/dev/null || echo "")
fi

# Output based on format
case "$FORMAT" in
    json)
        echo "$LOG_ENTRIES"
        ;;
    stats)
        echo "📊 Decision Log Statistics"
        echo "=========================="
        echo ""

        TOTAL=$(echo "$LOG_ENTRIES" | wc -l | tr -d ' ')
        BLOCKS=$(echo "$LOG_ENTRIES" | jq -r 'select(.decision=="block")' 2>/dev/null | wc -l | tr -d ' ')
        APPROVES=$((TOTAL - BLOCKS))

        echo "Total decisions:  $TOTAL"
        echo -e "  Continue (block): ${GREEN}$BLOCKS${NC}"
        echo -e "  Stop (approve):   ${YELLOW}$APPROVES${NC}"
        echo ""

        # Path breakdown
        echo "Decision paths:"
        PERM=$(echo "$LOG_ENTRIES" | jq -r 'select(.reason | test("Permission-seeking|User choice"))' 2>/dev/null | wc -l | tr -d ' ')
        HEUR=$(echo "$LOG_ENTRIES" | jq -r 'select(.reason | test("Heuristic"))' 2>/dev/null | wc -l | tr -d ' ')
        JUDGE=$((TOTAL - PERM - HEUR))
        echo "  Permission prefilter: $PERM"
        echo "  Heuristic prefilter:  $HEUR"
        echo "  Judge:                $JUDGE"

        if [[ "$TOTAL" -gt 0 ]]; then
            PREFILTER_PCT=$(echo "scale=1; ($PERM + $HEUR) * 100 / $TOTAL" | bc 2>/dev/null || echo "0")
            echo ""
            echo "Prefilter efficiency: ${PREFILTER_PCT}%"
        fi

        # Time range
        echo ""
        FIRST_TS=$(echo "$LOG_ENTRIES" | head -1 | jq -r '.timestamp // "?"')
        LAST_TS=$(echo "$LOG_ENTRIES" | tail -1 | jq -r '.timestamp // "?"')
        echo "Time range: $FIRST_TS → $LAST_TS"
        ;;
    pretty)
        echo "📋 Recent Decisions (last $LINES)"
        echo "=================================="
        echo ""

        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue

            TS=$(echo "$entry" | jq -r '.timestamp // "?"' | cut -d'T' -f2 | cut -d'.' -f1)
            DECISION=$(echo "$entry" | jq -r '.decision // "?"')
            REASON=$(echo "$entry" | jq -r '.reason // "?"' | head -c 80)
            SESSION=$(echo "$entry" | jq -r '.session_id // "?"' | head -c 8)

            if [[ "$DECISION" == "block" ]]; then
                echo -e "${GREEN}▶${NC} [$TS] ${GREEN}CONTINUE${NC} ($SESSION...)"
            else
                echo -e "${YELLOW}■${NC} [$TS] ${YELLOW}STOP${NC} ($SESSION...)"
            fi
            echo "    $REASON"
            echo ""
        done <<< "$LOG_ENTRIES"
        ;;
esac
