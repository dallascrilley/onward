#!/bin/bash
# settings.sh - Per-project settings reader
#
# Reads opt-in settings from .claude/redbull.local.md
# Uses YAML frontmatter format. Fail-closed: missing/invalid = safe defaults.
#
# Exported variables after settings_load():
# - REDBULL_ENABLED (true|false)
# - REDBULL_AGGRESSIVENESS (low|medium|high)

# Returns the settings file path
settings_get_path() {
    if [ -n "${REDBULL_SETTINGS_PATH:-}" ]; then
        printf '%s\n' "$REDBULL_SETTINGS_PATH"
        return 0
    fi
    printf '%s\n' ".claude/redbull.local.md"
}

# Set safe defaults
_settings_default() {
    REDBULL_ENABLED="true"
    REDBULL_AGGRESSIVENESS="high"
}

# Load settings from file (fail-closed: defaults on any error)
settings_load() {
    _settings_default

    local path
    path="$(settings_get_path)"
    [ -f "$path" ] || return 0
    [ -r "$path" ] || return 0

    local in_frontmatter="false"
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$in_frontmatter" = "false" ]; then
            [ "$line" = "---" ] && in_frontmatter="true"
            continue
        fi

        # End of frontmatter
        [ "$line" = "---" ] && break

        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Only "key: value" (single-line, no nested YAML)
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

# Apply aggressiveness to TRANSCRIPT_CONTEXT_LINES
settings_apply_aggressiveness() {
    case "$REDBULL_AGGRESSIVENESS" in
        low)    TRANSCRIPT_CONTEXT_LINES=6 ;;
        medium) TRANSCRIPT_CONTEXT_LINES=10 ;;
        high)   TRANSCRIPT_CONTEXT_LINES=14 ;;
    esac
}
