#!/bin/bash

# A CDPATH inherited from the caller makes `cd` echo its destination, which
# would corrupt every path resolved through a cd subshell below.
unset CDPATH

# Claude SessionStart Brief Plugin - SessionStart Hook Script
# Generates repository context brief at session start
# Opt-in via ONWARD_SESSION_BRIEF_ENABLED=true

# === Source Library Modules ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/emit.sh"
source "$SCRIPT_DIR/lib/debug.sh"
source "$SCRIPT_DIR/lib/config.sh"

# Load default configuration
load_defaults

# === Early exit: Disabled by default ===
if [ "${ONWARD_SESSION_BRIEF_ENABLED:-false}" != "true" ]; then
    emit_decision "approve" "Session brief disabled (set ONWARD_SESSION_BRIEF_ENABLED=true to enable)"
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

# Max lines to read from each doc file
MAX_DOC_LINES=60

# === Collect context snippets ===
BRIEF_CONTENT="# Session Brief

Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

---

"

# Helper: Append file content if exists
append_file_section() {
    local file_path="$1"
    local section_title="$2"
    local max_lines="${3:-$MAX_DOC_LINES}"

    if [ -f "$file_path" ]; then
        BRIEF_CONTENT="${BRIEF_CONTENT}## $section_title

\`\`\`
$(head -n "$max_lines" "$file_path" 2>/dev/null || echo "(error reading file)")
\`\`\`

"
        debug_log "file_added" --arg file "$(basename "$file_path")" --argjson lines "$max_lines"
    fi
}

# Collect from standard locations
append_file_section "AGENTS.md" "Agent Instructions"
append_file_section "README.md" "Project README"
append_file_section "CLAUDE.md" "Claude Instructions"
append_file_section "PLAN.md" "Current Plan"

# Find newest PLAN-OVERVIEW.md in docs/plans
NEWEST_PLAN=$(find docs/plans -type f -name "PLAN-OVERVIEW.md" 2>/dev/null | head -n 1)
if [ -n "$NEWEST_PLAN" ]; then
    append_file_section "$NEWEST_PLAN" "Plan Overview ($(dirname "$NEWEST_PLAN"))"
fi

# === Add Key Commands section ===
BRIEF_CONTENT="${BRIEF_CONTENT}## Key Commands

Common development commands (check package.json, Makefile, or README for full list):

\`\`\`bash
# Quality Gates
npm run typecheck  # or: tsc --noEmit
npm run lint       # or: eslint .
npm run test       # or: jest / vitest
npm run build      # or: tsc / webpack

# Git workflow
git status
git diff
git add <files>
git commit -m \"message\"
git push
\`\`\`

"

# === Add Quality Gates section ===
BRIEF_CONTENT="${BRIEF_CONTENT}## Quality Gates

Before every commit, run in this order (stop on first failure):

1. \`typecheck\` - Type safety validation
2. \`lint\` - Code style and quality
3. \`test\` - Unit and integration tests
4. \`build\` - Production build verification

Never use \`--no-verify\` to skip hooks.

"

# === Add Notes/Gotchas section ===
BRIEF_CONTENT="${BRIEF_CONTENT}## Notes & Gotchas

- Read existing code before modifying
- Prefer edits over new files
- Follow existing patterns and conventions
- Run quality gates before claiming completion
- Work is not done until changes are pushed

"

# === Write brief to .claude/session-brief.md ===
BRIEF_DIR=".claude"
BRIEF_FILE="$BRIEF_DIR/session-brief.md"

# Ensure .claude directory exists
mkdir -p "$BRIEF_DIR" 2>/dev/null || {
    debug_log "mkdir_failed"
    emit_decision "approve" "Failed to create .claude directory"
    exit 0
}

# Write atomically
TEMP_FILE=$(mktemp "$BRIEF_FILE.tmp.XXXXXX" 2>/dev/null) || {
    debug_log "mktemp_failed"
    emit_decision "approve" "Failed to create temp file"
    exit 0
}

if printf '%s\n' "$BRIEF_CONTENT" > "$TEMP_FILE"; then
    if mv -f "$TEMP_FILE" "$BRIEF_FILE" 2>/dev/null; then
        debug_log "brief_written" --arg file "$BRIEF_FILE"
        emit_decision "approve" "Session brief written to $BRIEF_FILE"
    else
        rm -f "$TEMP_FILE"
        debug_log "mv_failed"
        emit_decision "approve" "Failed to move brief to final location"
    fi
else
    rm -f "$TEMP_FILE"
    debug_log "write_failed"
    emit_decision "approve" "Failed to write brief content"
fi

exit 0
