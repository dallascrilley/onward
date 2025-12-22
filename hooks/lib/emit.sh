#!/bin/bash
# emit.sh - Single point of stdout JSON output for hooks
#
# All hook decisions must go through this emitter to ensure:
# - Consistent JSON format
# - Only stdout contains JSON (no debug output)
# - Easy to test and mock

emit_decision() {
  local decision="$1"
  local reason="$2"
  jq -n --arg d "$decision" --arg r "$reason" '{"decision": $d, "reason": $r}'
}
