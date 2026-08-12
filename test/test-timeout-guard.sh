#!/bin/bash
# ABOUTME: Verifies judge uses an available timeout wrapper for claude
# ABOUTME: Prevents unbounded hook execution when claude hangs

set -euo pipefail

# A CDPATH inherited from the caller makes `cd` echo its destination, which
# would corrupt every path resolved through a cd subshell below.
unset CDPATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"

TIMEOUT_CALLED_FILE="$TMP_DIR/timeout-called"

# Fake claude that would otherwise run long enough to be noticeable.
cat > "$BIN_DIR/claude" <<'EOF'
#!/bin/bash
sleep 1
printf '%s' '[{"structured_output":{"should_continue":false,"reasoning":"stub"}}]'
EOF
chmod +x "$BIN_DIR/claude"

# Fake timeout that records invocation and fails immediately.
cat > "$BIN_DIR/timeout" <<'EOF'
#!/bin/bash
echo "called" >> "${TIMEOUT_CALLED_FILE:-/tmp/timeout-called}"
exit 124
EOF
chmod +x "$BIN_DIR/timeout"

export PATH="$BIN_DIR:$PATH"
export TIMEOUT_CALLED_FILE

source "$REPO_ROOT/hooks/lib/judge.sh"

RECENT_CONTEXT='[{"role":"assistant","content":"Working on it."}]'

judge_should_continue "$RECENT_CONTEXT" "fake-model" "$TMP_DIR/work" >/dev/null 2>&1 || true

if [ ! -f "$TIMEOUT_CALLED_FILE" ]; then
    echo "Expected timeout wrapper to be used, but it was not." >&2
    exit 1
fi

echo "ok: timeout wrapper used"
