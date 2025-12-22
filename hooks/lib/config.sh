#!/bin/bash
# config.sh - Configuration defaults
#
# Loads default configuration values. Future versions will support
# per-project settings override.

load_defaults() {
    MAX_CONTINUATIONS=3
    THROTTLE_WINDOW_SECONDS=300
    TRANSCRIPT_CONTEXT_LINES=10
    CLAUDE_MODEL="haiku"
    CLAUDE_WORK_DIR="$HOME/.claude/double-shot-latte"
}
