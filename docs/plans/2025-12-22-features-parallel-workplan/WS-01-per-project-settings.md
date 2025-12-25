--- SELF-CONTAINED PLAN ---

# Per-Project Settings (WS-01) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Add an opt-in, per-project settings file that can disable the plugin and control aggressiveness without changing default behavior when the file is missing.

**Architecture:** Implement a strict, fail-closed YAML-frontmatter parser for `.claude/redbull.local.md` that only accepts a small allowlist of keys. The Stop hook reads settings once and applies safe defaults if anything is missing/invalid.

**Tech Stack:** Bash + `jq`.

## Summary

Right now, the Stop hook behavior is effectively hard-coded. Your task is to add a per-project settings file reader and wire `enabled` and `aggressiveness` into the Stop hook so users can safely opt out or tune behavior.

## Prerequisites

- WS-00 merged to `main` (expects `hooks/lib/*.sh` and modular Stop hook).
- Proving commands:
  - `./test/evals/run-evals.sh`
  - `./test/test-working-directory.sh`
  - New: `./test/test-settings.sh` (added by this workstream)

## Settings Contract (Minimal, Safe, Fail-Closed)

**Path (default):** `.claude/redbull.local.md` in the project root (hook CWD).  
**Override (testing/automation):** `REDBULL_SETTINGS_PATH=/absolute/path/to/file.md`

**Format:** Markdown file with YAML frontmatter:

```md
---
enabled: true
aggressiveness: medium # low|medium|high
---

(optional markdown body ignored by parser)
```

**Fail-closed defaults (when missing/invalid):**
- `enabled=true` (default behavior unchanged)
- `aggressiveness=high` (matches the current “aggressive version” intent)

## Files

- Create:
  - `hooks/lib/settings.sh`
  - `test/test-settings.sh`
- Modify:
  - `hooks/claude-judge-continuation.sh`

## Implementation Steps

### Task 1: Implement `hooks/lib/settings.sh`

**Step 1:** Create `hooks/lib/settings.sh` with these public functions:

- `settings_get_path()` → echoes the settings path
- `settings_load()` → sets exported variables:
  - `REDBULL_ENABLED` (`true|false`)
  - `REDBULL_AGGRESSIVENESS` (`low|medium|high`)

**Step 2:** Implement `settings_get_path()`:

```bash
settings_get_path() {
  if [ -n "${REDBULL_SETTINGS_PATH:-}" ]; then
    printf '%s\n' "$REDBULL_SETTINGS_PATH"
    return 0
  fi
  printf '%s\n' ".claude/redbull.local.md"
}
```

**Step 3:** Implement a strict YAML-frontmatter reader:
- Only read if the file exists and is readable.
- Only parse lines between the first `---` and the next `---`.
- Only accept these keys: `enabled`, `aggressiveness`.
- Ignore comments and blank lines.
- Reject multiline values and nested YAML.

Example parser skeleton:

```bash
_settings_default() {
  REDBULL_ENABLED="true"
  REDBULL_AGGRESSIVENESS="high"
}

settings_load() {
  _settings_default

  local path
  path="$(settings_get_path)"
  [ -f "$path" ] || return 0
  [ -r "$path" ] || return 0

  local in_frontmatter="false"
  while IFS= read -r line; do
    if [ "$in_frontmatter" = "false" ]; then
      [ "$line" = "---" ] && in_frontmatter="true"
      continue
    fi

    [ "$line" = "---" ] && break
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # Only "key: value" (single-line)
    local key="${line%%:*}"
    local value="${line#*:}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

    case "$key" in
      enabled)
        case "$value" in
          true|false) REDBULL_ENABLED="$value" ;;
        esac
        ;;
      aggressiveness)
        case "$value" in
          low|medium|high) REDBULL_AGGRESSIVENESS="$value" ;;
        esac
        ;;
    esac
  done < "$path"
}
```

**Step 4:** Add `bash -n hooks/lib/settings.sh` to your local sanity loop.

### Task 2: Wire settings into the Stop hook

**Step 1:** Source settings in `hooks/claude-judge-continuation.sh` after WS-00 sources:

```bash
source "$SCRIPT_DIR/lib/settings.sh"
```

**Step 2:** Load settings near the top (after recursion check, before expensive work):
- Call: `settings_load`

**Step 3:** Apply `enabled` gate:
- If `REDBULL_ENABLED=false`, then:
  - `emit_decision "approve" "Disabled by per-project settings"`
  - Exit 0

**Step 4 (minimal aggressiveness wiring):**
- For now, use `REDBULL_AGGRESSIVENESS` to tune only one knob deterministically:
  - `low` → `TRANSCRIPT_CONTEXT_LINES=6`
  - `medium` → `TRANSCRIPT_CONTEXT_LINES=10`
  - `high` → `TRANSCRIPT_CONTEXT_LINES=14`
- Keep all other defaults unchanged.

### Task 3: Add a deterministic settings test

**Step 1:** Create `test/test-settings.sh` that:
- Creates a temp directory with a `.claude/redbull.local.md`
- Creates a temp transcript file
- Executes the hook with `REDBULL_SETTINGS_PATH` pointing to the temp settings file
- Asserts `decision` is `approve` when `enabled: false`

Suggested outline:

```bash
#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/claude-judge-continuation.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

event="$(jq -n --arg transcript_path "$tmp/transcript.ndjson" '{stop_hook_active:false, transcript_path:$transcript_path, session_id:"settings-test"}')"
out="$(echo "$event" | REDBULL_SETTINGS_PATH="$tmp/.claude/redbull.local.md" "$HOOK")"

decision="$(printf '%s' "$out" | jq -r '.decision')"
[ "$decision" = "approve" ]
```

**Step 2:** `chmod +x test/test-settings.sh`

### Task 4: Prove no regressions

Run:
- `./test/test-settings.sh`
- `./test/evals/run-evals.sh`
- `./test/test-working-directory.sh`

## Immediate Next Task

Create `hooks/lib/settings.sh` with a strict YAML-frontmatter parser for `enabled` + `aggressiveness`.

## First Step

```bash
cd /Users/dallascrilley/Code/dallas-plugin-marketplace/redbull
sed -n '1,120p' hooks/claude-judge-continuation.sh
```

