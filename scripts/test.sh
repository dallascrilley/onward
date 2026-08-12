#!/bin/bash
# test.sh - Run the whole suite: hook tests, then the eval scenarios.
#
# Usage:
#   ./scripts/test.sh            # hook tests + eval scenarios
#   ./scripts/test.sh --fast     # hook tests only (skips the ~3 minute evals)
#
# Exit code is non-zero if any test script or eval scenario fails.

set -uo pipefail

# A CDPATH inherited from the caller makes `cd` echo its destination, which
# would end up inside the paths resolved below.
unset CDPATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FAST=false
if [ "${1:-}" = "--fast" ]; then
    FAST=true
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to run the suite. Install it and try again." >&2
    exit 1
fi

cd "$REPO_ROOT" || exit 1

# Several tests exercise the default state directory, which lives under $HOME.
# Point HOME at a throwaway directory so a test run never touches real plugin
# state on the machine running it.
SUITE_HOME=$(mktemp -d)
cleanup_suite_home() {
    rm -rf "$SUITE_HOME"
}
trap cleanup_suite_home EXIT
export HOME="$SUITE_HOME"

passed=0
failed=0
failed_names=""

echo "=== Hook tests ==="
for test_file in test/test-*.sh; do
    [ -f "$test_file" ] || continue
    if bash "$test_file" >/dev/null 2>&1; then
        echo "  PASS  $test_file"
        passed=$((passed + 1))
    else
        echo "  FAIL  $test_file"
        failed=$((failed + 1))
        failed_names="${failed_names}${test_file}"$'\n'
    fi
done

echo ""
echo "Hook tests: $passed passed, $failed failed"

if [ "$FAST" = "false" ]; then
    echo ""
    echo "=== Eval scenarios ==="
    if bash test/evals/run-evals.sh; then
        echo "Eval scenarios: passed"
    else
        echo "Eval scenarios: FAILED"
        failed=$((failed + 1))
        failed_names="${failed_names}test/evals/run-evals.sh"$'\n'
    fi
fi

if [ "$failed" -gt 0 ]; then
    echo ""
    echo "Failed:"
    printf '%s' "$failed_names" | sed 's/^/  /'
    echo ""
    echo "Re-run a single test directly to see its output, for example:"
    echo "  bash test/test-handoff.sh"
    exit 1
fi

echo ""
echo "All tests passed."
exit 0
