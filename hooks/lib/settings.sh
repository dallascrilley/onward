#!/bin/bash
# settings.sh - Per-project settings reader
#
# Reads opt-in settings from .claude/onward.local.md
# Uses YAML frontmatter format. Fail-closed: missing/invalid = safe defaults.
#
# Exported variables after settings_load():
# - ONWARD_ENABLED (true|false)
# - ONWARD_AGGRESSIVENESS (low|medium|high)

# Returns the settings file path
settings_get_path() {
    if [ -n "${ONWARD_SETTINGS_PATH:-}" ]; then
        printf '%s\n' "$ONWARD_SETTINGS_PATH"
        return 0
    fi
    printf '%s\n' ".claude/onward.local.md"
}

# Set safe defaults
_settings_default() {
    ONWARD_ENABLED="true"
    ONWARD_AGGRESSIVENESS="high"
    DEFINITION_OF_DONE=""
    DOD_ENFORCEMENT="advisory"
}

# Load settings from file (fail-closed: defaults on any error)
settings_load() {
    _settings_default

    local path
    path="$(settings_get_path)"
    [ -f "$path" ] || return 0
    [ -r "$path" ] || return 0

    local in_frontmatter="false"
    local in_dod_list="false"
    local dod_rules=""
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

        # Handle multi-line YAML list items (indented lines starting with "- ")
        if [ "$in_dod_list" = "true" ]; then
            if [[ "$line" =~ ^[[:space:]]+-[[:space:]](.+)$ ]]; then
                local rule="${BASH_REMATCH[1]}"
                if [ -n "$dod_rules" ]; then
                    dod_rules="${dod_rules}"$'\n'"${rule}"
                else
                    dod_rules="${rule}"
                fi
                continue
            else
                in_dod_list="false"
                # Fall through to process this line normally
            fi
        fi

        # Only "key: value" (single-line, no nested YAML)
        local key="${line%%:*}"
        local value="${line#*:}"
        key="$(printf '%s' "$key" | tr -d '[:space:]')"
        value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        case "$key" in
            enabled)
                case "$value" in
                    true|false) ONWARD_ENABLED="$value" ;;
                esac
                ;;
            aggressiveness)
                case "$value" in
                    low|medium|high) ONWARD_AGGRESSIVENESS="$value" ;;
                esac
                ;;
            dod_enforcement)
                case "$value" in
                    advisory|strict) DOD_ENFORCEMENT="$value" ;;
                esac
                ;;
            definition_of_done)
                in_dod_list="true"
                ;;
        esac
    done < "$path"

    DEFINITION_OF_DONE="$dod_rules"
}

# Apply aggressiveness to TRANSCRIPT_CONTEXT_LINES
settings_apply_aggressiveness() {
    case "$ONWARD_AGGRESSIVENESS" in
        low)    TRANSCRIPT_CONTEXT_LINES=6 ;;
        medium) TRANSCRIPT_CONTEXT_LINES=10 ;;
        high)   TRANSCRIPT_CONTEXT_LINES=14 ;;
    esac
}
