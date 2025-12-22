#!/bin/bash
# test-settings.sh - Test per-project settings functionality
#
# Tests:
# 1. enabled=false should approve stop without calling judge
# 2. Settings file parsing (unit test of settings_load)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/claude-judge-continuation.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass_count=0
fail_count=0

# Test 1: enabled=false should approve stop
test_disabled() {
    echo "🧩 Test: enabled=false approves stop"

    mkdir -p "$tmp/.claude"
    cat > "$tmp/.claude/redbull.local.md" <<'EOF'
---
enabled: false
aggressiveness: high
---
EOF

    cat > "$tmp/transcript.ndjson" <<'EOF'
{"role":"user","content":"test"}
{"role":"assistant","content":"Next I will do X."}
EOF

    local event
    event="$(jq -n --arg tp "$tmp/transcript.ndjson" '{stop_hook_active:false, transcript_path:$tp, session_id:"test"}')"

    local out
    out="$(echo "$event" | REDBULL_SETTINGS_PATH="$tmp/.claude/redbull.local.md" "$HOOK" 2>/dev/null)" || true

    local decision reason
    decision="$(printf '%s' "$out" | jq -r '.decision // "error"')"
    reason="$(printf '%s' "$out" | jq -r '.reason // ""')"

    if [ "$decision" = "approve" ] && [[ "$reason" == *"Disabled by per-project settings"* ]]; then
        echo -e "   ${GREEN}✓${NC} PASS (decision: $decision, reason contains 'Disabled')"
        ((pass_count++)) || true || true
    else
        echo -e "   ${RED}✗${NC} FAIL (decision: $decision, reason: $reason)"
        ((fail_count++)) || true || true
    fi
}

# Test 2: Unit test settings_load directly
test_settings_parsing() {
    echo "🧩 Test: settings_load parses correctly"

    mkdir -p "$tmp/.claude"
    cat > "$tmp/.claude/redbull.local.md" <<'EOF'
---
enabled: true
aggressiveness: low
---
Optional markdown body here
EOF

    # Source settings module and test
    source "$REPO_ROOT/hooks/lib/settings.sh"

    REDBULL_SETTINGS_PATH="$tmp/.claude/redbull.local.md"
    settings_load

    if [ "$REDBULL_ENABLED" = "true" ] && [ "$REDBULL_AGGRESSIVENESS" = "low" ]; then
        echo -e "   ${GREEN}✓${NC} PASS (enabled=$REDBULL_ENABLED, aggressiveness=$REDBULL_AGGRESSIVENESS)"
        ((pass_count++)) || true
    else
        echo -e "   ${RED}✗${NC} FAIL (enabled=$REDBULL_ENABLED, aggressiveness=$REDBULL_AGGRESSIVENESS)"
        ((fail_count++)) || true
    fi
}

# Test 3: Missing settings file uses defaults
test_missing_file() {
    echo "🧩 Test: missing settings uses defaults"

    source "$REPO_ROOT/hooks/lib/settings.sh"

    REDBULL_SETTINGS_PATH="$tmp/nonexistent.md"
    settings_load

    if [ "$REDBULL_ENABLED" = "true" ] && [ "$REDBULL_AGGRESSIVENESS" = "high" ]; then
        echo -e "   ${GREEN}✓${NC} PASS (defaults: enabled=$REDBULL_ENABLED, aggressiveness=$REDBULL_AGGRESSIVENESS)"
        ((pass_count++)) || true
    else
        echo -e "   ${RED}✗${NC} FAIL (enabled=$REDBULL_ENABLED, aggressiveness=$REDBULL_AGGRESSIVENESS)"
        ((fail_count++)) || true
    fi
}

# Test 4: Invalid values use defaults
test_invalid_values() {
    echo "🧩 Test: invalid values use defaults"

    mkdir -p "$tmp/.claude"
    cat > "$tmp/.claude/redbull.local.md" <<'EOF'
---
enabled: invalid
aggressiveness: extreme
---
EOF

    source "$REPO_ROOT/hooks/lib/settings.sh"

    REDBULL_SETTINGS_PATH="$tmp/.claude/redbull.local.md"
    settings_load

    if [ "$REDBULL_ENABLED" = "true" ] && [ "$REDBULL_AGGRESSIVENESS" = "high" ]; then
        echo -e "   ${GREEN}✓${NC} PASS (defaults: enabled=$REDBULL_ENABLED, aggressiveness=$REDBULL_AGGRESSIVENESS)"
        ((pass_count++)) || true
    else
        echo -e "   ${RED}✗${NC} FAIL (enabled=$REDBULL_ENABLED, aggressiveness=$REDBULL_AGGRESSIVENESS)"
        ((fail_count++)) || true
    fi
}

# Test 5: Aggressiveness affects context lines
test_aggressiveness_levels() {
    echo "🧩 Test: aggressiveness sets context lines"

    source "$REPO_ROOT/hooks/lib/config.sh"
    source "$REPO_ROOT/hooks/lib/settings.sh"

    local all_pass=true

    for level in low medium high; do
        mkdir -p "$tmp/.claude"
        cat > "$tmp/.claude/redbull.local.md" <<EOF
---
enabled: true
aggressiveness: $level
---
EOF
        REDBULL_SETTINGS_PATH="$tmp/.claude/redbull.local.md"
        load_defaults
        settings_load
        settings_apply_aggressiveness

        local expected
        case "$level" in
            low)    expected=6 ;;
            medium) expected=10 ;;
            high)   expected=14 ;;
        esac

        if [ "$TRANSCRIPT_CONTEXT_LINES" = "$expected" ]; then
            echo -e "   ${GREEN}✓${NC} $level → $TRANSCRIPT_CONTEXT_LINES lines"
        else
            echo -e "   ${RED}✗${NC} $level → $TRANSCRIPT_CONTEXT_LINES (expected $expected)"
            all_pass=false
        fi
    done

    if $all_pass; then
        ((pass_count++)) || true
    else
        ((fail_count++)) || true
    fi
}

echo "🧪 Testing Per-Project Settings"
echo "================================"
echo

test_disabled
test_settings_parsing
test_missing_file
test_invalid_values
test_aggressiveness_levels

echo
echo "================================"
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi

echo -e "${GREEN}🎉 All settings tests passed!${NC}"
