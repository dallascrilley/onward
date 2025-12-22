#!/bin/bash

# Claude Guardrails Plugin - PreToolUse Hook Script
# Blocks dangerous commands before execution
# Opt-in via REDBULL_GUARDRAILS_ENABLED=true

# === Source Library Modules ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/emit.sh"
source "$SCRIPT_DIR/lib/debug.sh"
source "$SCRIPT_DIR/lib/config.sh"

# Load default configuration
load_defaults

# === Early exit: Disabled by default ===
if [ "${REDBULL_GUARDRAILS_ENABLED:-false}" != "true" ]; then
    emit_decision "approve" "Guardrails disabled (set REDBULL_GUARDRAILS_ENABLED=true to enable)"
    exit 0
fi

# Read the hook event data
EVENT=$(cat)

# Validate input is valid JSON
if ! echo "$EVENT" | jq empty 2>/dev/null; then
    debug_log "invalid_input"
    emit_decision "approve" "Invalid JSON input: could not parse hook event"
    exit 0
fi

# Extract command from various possible payload structures
# PreToolUse events can have different payload shapes depending on tool type
COMMAND=""

# Try extracting from common payload paths
COMMAND=$(echo "$EVENT" | jq -r '
    .payload.command //
    .payload.arguments.command //
    .tool_input.command //
    .parameters.command //
    ""
' 2>/dev/null)

# If no command found, approve (not a bash command)
if [ -z "$COMMAND" ] || [ "$COMMAND" = "null" ]; then
    emit_decision "approve" "No command found in payload"
    exit 0
fi

debug_log "command_extracted" --arg command "$COMMAND"

# === Dangerous pattern detection ===

# Pattern 1: rm -rf / or rm -rf /*
if echo "$COMMAND" | grep -qE '^\s*rm\s+.*-.*r.*f.*/(\s|$)'; then
    emit_decision "block" "Blocked dangerous command: rm -rf /. Suggest: verify target directory before deletion"
    exit 0
fi

# Pattern 2: rm -rf ~
if echo "$COMMAND" | grep -qE '^\s*rm\s+.*-.*r.*f.*~'; then
    emit_decision "block" "Blocked dangerous command: rm -rf ~. Suggest: verify target directory before deletion"
    exit 0
fi

# Pattern 3: git reset --hard (without specific commit)
if echo "$COMMAND" | grep -qE '^\s*git\s+reset\s+--hard\s*$'; then
    emit_decision "block" "Blocked dangerous command: git reset --hard without target. Suggest: git reset --hard <commit-sha> or git restore <files>"
    exit 0
fi

# Pattern 4: git clean -fdx (destructive clean)
if echo "$COMMAND" | grep -qE '^\s*git\s+clean\s+.*-.*f.*d.*x'; then
    emit_decision "block" "Blocked dangerous command: git clean -fdx. Suggest: git status to review, then git clean -n to preview deletions first"
    exit 0
fi

# Pattern 5: curl/wget pipe to sh/bash
if echo "$COMMAND" | grep -qE '(curl|wget).*\|\s*(bash|sh)'; then
    emit_decision "block" "Blocked dangerous command: piping download to shell. Suggest: review script content first, then execute if safe"
    exit 0
fi

# Pattern 6: chmod 777 (overly permissive)
if echo "$COMMAND" | grep -qE '^\s*chmod\s+777'; then
    emit_decision "block" "Blocked overly permissive command: chmod 777. Suggest: use minimal permissions (e.g., chmod 755 for executables, 644 for files)"
    exit 0
fi

# No dangerous patterns detected
emit_decision "approve" "Command passed guardrail checks"
exit 0
