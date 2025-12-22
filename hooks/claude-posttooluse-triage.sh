#!/bin/bash

# Claude PostToolUse Triage Plugin - PostToolUse Hook Script
# Detects tool failures and suggests fixes
# Opt-in via REDBULL_TRIAGE_ENABLED=true

# === Source Library Modules ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/emit.sh"
source "$SCRIPT_DIR/lib/debug.sh"
source "$SCRIPT_DIR/lib/config.sh"

# Load default configuration
load_defaults

# === Early exit: Disabled by default ===
if [ "${REDBULL_TRIAGE_ENABLED:-false}" != "true" ]; then
    emit_decision "approve" "Triage disabled (set REDBULL_TRIAGE_ENABLED=true to enable)"
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

# Extract from multiple possible payload structures
EXIT_CODE=$(echo "$EVENT" | jq -r '
    .payload.exit_code //
    .payload.result.exit_code //
    .tool_result.exit_code //
    null
' 2>/dev/null)

# If exit code is null, 0, or not a number, no failure to triage
if [ -z "$EXIT_CODE" ] || [ "$EXIT_CODE" = "null" ] || [ "$EXIT_CODE" = "0" ]; then
    emit_decision "approve" "No failure detected (exit code: ${EXIT_CODE:-unknown})"
    exit 0
fi

# Extract command and output
COMMAND=$(echo "$EVENT" | jq -r '
    .payload.command //
    .payload.arguments.command //
    .tool_input.command //
    "unknown command"
' 2>/dev/null)

STDOUT=$(echo "$EVENT" | jq -r '
    .payload.stdout //
    .payload.result.stdout //
    .tool_result.stdout //
    ""
' 2>/dev/null)

STDERR=$(echo "$EVENT" | jq -r '
    .payload.stderr //
    .payload.result.stderr //
    .tool_result.stderr //
    ""
' 2>/dev/null)

debug_log "failure_detected" \
    --argjson exit_code "${EXIT_CODE:-0}" \
    --arg command "$COMMAND"

# === Build triage report ===
MAX_OUTPUT_LINES=40
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

TRIAGE_CONTENT="# Tool Failure Triage

**Timestamp:** $TIMESTAMP
**Exit Code:** $EXIT_CODE
**Command:** \`$COMMAND\`

---

## Error Output

"

# Add stderr if present
if [ -n "$STDERR" ] && [ "$STDERR" != "null" ]; then
    STDERR_TRUNCATED=$(echo "$STDERR" | head -n "$MAX_OUTPUT_LINES")
    TRIAGE_CONTENT="${TRIAGE_CONTENT}### stderr

\`\`\`
$STDERR_TRUNCATED
\`\`\`

"
fi

# Add stdout if present
if [ -n "$STDOUT" ] && [ "$STDOUT" != "null" ]; then
    STDOUT_TRUNCATED=$(echo "$STDOUT" | head -n "$MAX_OUTPUT_LINES")
    TRIAGE_CONTENT="${TRIAGE_CONTENT}### stdout

\`\`\`
$STDOUT_TRUNCATED
\`\`\`

"
fi

# === Heuristic-based suggestions ===
TRIAGE_CONTENT="${TRIAGE_CONTENT}## Suggested Next Steps

"

# Detect common error patterns and suggest fixes
SUGGESTIONS_ADDED=false

# Pattern: command not found
if echo "$STDERR" | grep -qi "command not found"; then
    TRIAGE_CONTENT="${TRIAGE_CONTENT}- **Command not found**: Check if the tool is installed and available in PATH
  - Try: \`which <command>\` or \`command -v <command>\`
  - Install if missing: \`brew install <tool>\`, \`npm install -g <package>\`, etc.

"
    SUGGESTIONS_ADDED=true
fi

# Pattern: permission denied
if echo "$STDERR" | grep -qi "permission denied"; then
    TRIAGE_CONTENT="${TRIAGE_CONTENT}- **Permission denied**: Check file/directory permissions
  - Try: \`ls -la <path>\`
  - Fix permissions: \`chmod +x <file>\` or \`chmod 644 <file>\`
  - Check ownership: \`chown <user>:<group> <file>\`

"
    SUGGESTIONS_ADDED=true
fi

# Pattern: Cannot find module (Node.js)
if echo "$STDERR" | grep -qi "Cannot find module\|MODULE_NOT_FOUND"; then
    TRIAGE_CONTENT="${TRIAGE_CONTENT}- **Module not found**: Install missing dependencies
  - Try: \`npm install\` or \`yarn install\`
  - Check package.json for the missing module
  - Clear cache if needed: \`npm cache clean --force\`

"
    SUGGESTIONS_ADDED=true
fi

# Pattern: No such file or directory
if echo "$STDERR" | grep -qi "No such file or directory"; then
    TRIAGE_CONTENT="${TRIAGE_CONTENT}- **File not found**: Verify file path and existence
  - Try: \`ls -la <directory>\`
  - Check current working directory: \`pwd\`
  - Verify relative vs absolute paths

"
    SUGGESTIONS_ADDED=true
fi

# Pattern: Connection refused / timeout (network)
if echo "$STDERR" | grep -qi "connection refused\|timeout\|could not resolve"; then
    TRIAGE_CONTENT="${TRIAGE_CONTENT}- **Network error**: Check connectivity and service availability
  - Try: \`ping <host>\` or \`curl <url>\`
  - Check if service is running: \`ps aux | grep <service>\`
  - Verify firewall/proxy settings

"
    SUGGESTIONS_ADDED=true
fi

# Pattern: Syntax error (code)
if echo "$STDERR" | grep -qi "SyntaxError\|syntax error\|parse error"; then
    TRIAGE_CONTENT="${TRIAGE_CONTENT}- **Syntax error**: Review code for syntax mistakes
  - Check line number in error message
  - Verify matching brackets, quotes, parentheses
  - Run linter: \`eslint <file>\` or equivalent

"
    SUGGESTIONS_ADDED=true
fi

# Default suggestion if no patterns matched
if [ "$SUGGESTIONS_ADDED" = false ]; then
    TRIAGE_CONTENT="${TRIAGE_CONTENT}- **Generic failure**: Review error output above
  - Rerun with verbose/debug flags: \`-v\`, \`--verbose\`, \`--debug\`
  - Check documentation for exit code $EXIT_CODE
  - Search error message in project issues or Stack Overflow

"
fi

# === Write triage to .claude/triage.md ===
TRIAGE_DIR=".claude"
TRIAGE_FILE="$TRIAGE_DIR/triage.md"

# Ensure .claude directory exists
mkdir -p "$TRIAGE_DIR" 2>/dev/null || {
    debug_log "mkdir_failed"
    emit_decision "approve" "Failed to create .claude directory"
    exit 0
}

# Write atomically
TEMP_FILE=$(mktemp "$TRIAGE_FILE.tmp.XXXXXX" 2>/dev/null) || {
    debug_log "mktemp_failed"
    emit_decision "approve" "Failed to create temp file"
    exit 0
}

if printf '%s\n' "$TRIAGE_CONTENT" > "$TEMP_FILE"; then
    if mv -f "$TEMP_FILE" "$TRIAGE_FILE" 2>/dev/null; then
        debug_log "triage_written" --arg file "$TRIAGE_FILE" --argjson exit_code "$EXIT_CODE"
        emit_decision "approve" "Triage report written to $TRIAGE_FILE (exit code: $EXIT_CODE)"
    else
        rm -f "$TEMP_FILE"
        debug_log "mv_failed"
        emit_decision "approve" "Failed to move triage to final location"
    fi
else
    rm -f "$TEMP_FILE"
    debug_log "write_failed"
    emit_decision "approve" "Failed to write triage content"
fi

exit 0
