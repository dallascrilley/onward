#!/bin/bash

# Test: explain.sh --verbose shows DoD mode and rule count when present.

set -euo pipefail

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPLAIN_SCRIPT="$SCRIPT_DIR/../scripts/explain.sh"

require_cmd jq
[ -x "$EXPLAIN_SCRIPT" ] || fail "Explain script not found or not executable: $EXPLAIN_SCRIPT"

TEMP_DIR="$(mktemp -d "/tmp/redbull-explain-XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

DECISION_FILE="$TEMP_DIR/last_decision.json"

cat > "$DECISION_FILE" <<EOF
{
  "timestamp": "2025-12-22T00:00:00Z",
  "session_id": "test-session",
  "decision": "approve",
  "reason": "ok",
  "dod_enforcement": "strict",
  "dod_rules_count": 2,
  "evaluation": {
    "should_continue": false,
    "reasoning": "test",
    "confidence": 0.9,
    "decision_category": "task_completion",
    "risk_level": "low",
    "signals": ["explicit_completion"],
    "reasons": ["test"]
  }
}
EOF

output=$(
    LAST_DECISION_FILE="$DECISION_FILE" \
    "$EXPLAIN_SCRIPT" --verbose
)

printf '%s' "$output" | grep -Fq "DoD Mode:      strict" || fail "Missing DoD Mode in verbose output"
printf '%s' "$output" | grep -Fq "DoD Rules:     2" || fail "Missing DoD Rules count in verbose output"

echo "PASS: explain.sh shows DoD metadata"
