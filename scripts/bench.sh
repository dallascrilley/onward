#!/bin/bash
# bench.sh - lightweight performance benchmarks for hook flow

set -euo pipefail

ROOT_DIR="${BENCH_ROOT:-}"

RUNS=10
LABEL="current"
BASELINE_REF=""
NO_BASELINE=false
ROOT_OVERRIDE=""
SKIP_EVALS=false

usage() {
    cat <<'USAGE'
Usage: scripts/bench.sh [options]

Options:
  --runs N         Number of iterations per benchmark (default: 10)
  --baseline REF   Git ref for before/after comparison (creates worktree)
  --label NAME     Label for this run (default: current)
  --skip-evals     Skip full eval suite timing (faster runs)
  --no-baseline    Internal: skip baseline worktree logic
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --runs)
            RUNS="$2"
            shift 2
            ;;
        --baseline)
            BASELINE_REF="$2"
            shift 2
            ;;
        --label)
            LABEL="$2"
            shift 2
            ;;
        --no-baseline)
            NO_BASELINE=true
            shift
            ;;
        --root)
            ROOT_OVERRIDE="$2"
            shift 2
            ;;
        --skip-evals)
            SKIP_EVALS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ -n "$ROOT_OVERRIDE" ]; then
    ROOT_DIR="$ROOT_OVERRIDE"
fi

if [ -z "$ROOT_DIR" ]; then
    ROOT_DIR="$(git rev-parse --show-toplevel)"
fi

time_cmd() {
    if [ -x "/usr/bin/time" ]; then
        echo "/usr/bin/time -p"
        return 0
    fi
    echo "time -p"
}

collect_times() {
    local label="$1"
    local cmd="$2"
    local runs="$3"
    local out_file="$4"
    local timer
    timer="$(time_cmd)"
    : > "$out_file"
    for _ in $(seq 1 "$runs"); do
        local tmp
        tmp="$(mktemp)"
        # shellcheck disable=SC2086
        $timer bash -c "$cmd" 2> "$tmp" >/dev/null || true
        awk '/^real /{print $2}' "$tmp" >> "$out_file"
        rm -f "$tmp"
    done
    printf '%s\n' "$label" >/dev/null
}

print_stats() {
    local label="$1"
    local file="$2"
    local count
    count=$(wc -l < "$file" | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        echo "$label: no samples"
        return 0
    fi
    local sorted
    sorted="$(mktemp)"
    sort -n "$file" > "$sorted"
    local median_idx p95_idx
    median_idx=$(( (count + 1) / 2 ))
    p95_idx=$(( (count * 95 + 99) / 100 ))
    local median p95 avg
    median=$(sed -n "${median_idx}p" "$sorted")
    p95=$(sed -n "${p95_idx}p" "$sorted")
    avg=$(awk '{sum+=$1} END{printf "%.4f", sum/NR}' "$sorted")
    echo "$label: runs=$count avg=${avg}s median=${median}s p95=${p95}s"
    rm -f "$sorted"
}

bench_current_repo() {
    local label="$1"
    local runs="$2"
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    echo ""
    echo "=== Benchmark: $label ==="

    # 1) End-to-end eval suite
    if [ "$SKIP_EVALS" = "false" ]; then
        collect_times "evals" "cd \"$ROOT_DIR\" && ./test/evals/run-evals.sh" "$runs" "$tmp_dir/evals.txt"
        print_stats "evals" "$tmp_dir/evals.txt"
    else
        echo "evals: skipped"
    fi

    # Prepare transcripts from scenario fixtures (pick stable files)
    local stop_scenario=""
    local continue_scenario=""
    for candidate in \
        "$ROOT_DIR/test/evals/scenarios/01-plan-presentation-asking-approval.json" \
        "$ROOT_DIR/test/evals/scenarios/03-asking-for-user-decision.json" \
        "$ROOT_DIR/test/evals/scenarios/10-clarification-needed.json"; do
        if [ -f "$candidate" ]; then
            stop_scenario="$candidate"
            break
        fi
    done
    for candidate in \
        "$ROOT_DIR/test/evals/scenarios/02-work-incomplete-obvious-next-steps.json" \
        "$ROOT_DIR/test/evals/scenarios/06-explicit-next-steps-mentioned.json" \
        "$ROOT_DIR/test/evals/scenarios/05-mid-implementation-with-todos.json"; do
        if [ -f "$candidate" ]; then
            continue_scenario="$candidate"
            break
        fi
    done

    local stop_transcript="$tmp_dir/stop.json"
    local continue_transcript="$tmp_dir/continue.json"
    local judge_transcript="$tmp_dir/judge.json"

    if [ -z "$stop_scenario" ] || [ -z "$continue_scenario" ]; then
        echo "Missing required scenarios for benchmark." >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    jq -c '.transcript' "$stop_scenario" > "$stop_transcript"
    jq -c '.transcript' "$continue_scenario" > "$continue_transcript"
    cat > "$judge_transcript" <<'EOF'
[
  {"role":"user","content":"Review the code changes"},
  {"role":"assistant","content":"I reviewed the changes. The updates look reasonable and align with the existing patterns."}
]
EOF

    # 2) Hook latency for representative cases
    collect_times "hook_stop" \
        "cd \"$ROOT_DIR\" && PATH=\"$ROOT_DIR/test/evals/bin:\$PATH\" EVAL_OFFLINE=1 bash ./hooks/claude-judge-continuation.sh <<< '{\"session_id\":\"bench\",\"transcript_path\":\"$stop_transcript\",\"stop_hook_active\":false}'" \
        "$runs" "$tmp_dir/hook_stop.txt"
    print_stats "hook_stop" "$tmp_dir/hook_stop.txt"

    collect_times "hook_continue" \
        "cd \"$ROOT_DIR\" && PATH=\"$ROOT_DIR/test/evals/bin:\$PATH\" EVAL_OFFLINE=1 bash ./hooks/claude-judge-continuation.sh <<< '{\"session_id\":\"bench\",\"transcript_path\":\"$continue_transcript\",\"stop_hook_active\":false}'" \
        "$runs" "$tmp_dir/hook_continue.txt"
    print_stats "hook_continue" "$tmp_dir/hook_continue.txt"

    collect_times "hook_judge" \
        "cd \"$ROOT_DIR\" && PATH=\"$ROOT_DIR/test/evals/bin:\$PATH\" EVAL_OFFLINE=1 bash ./hooks/claude-judge-continuation.sh <<< '{\"session_id\":\"bench\",\"transcript_path\":\"$judge_transcript\",\"stop_hook_active\":false}'" \
        "$runs" "$tmp_dir/hook_judge.txt"
    print_stats "hook_judge" "$tmp_dir/hook_judge.txt"

    # 3) Stall detector micro-bench
    local decision_log="$tmp_dir/decision_log.jsonl"
    for i in $(seq 1 12); do
        jq -nc \
            --arg hash "deadbeef" \
            --argjson conf "$(awk "BEGIN{print 0.9 - ($i * 0.02)}")" \
            --arg cat "incomplete_work" \
            '{context_hash:$hash, evaluation:{confidence:$conf, decision_category:$cat}}' >> "$decision_log"
    done

    collect_times "stall_detect" \
        "cd \"$ROOT_DIR\" && source hooks/lib/judge.sh && detect_stall \"deadbeef\" \"$decision_log\" >/dev/null" \
        "$runs" "$tmp_dir/stall_detect.txt"
    print_stats "stall_detect" "$tmp_dir/stall_detect.txt"

    # 4) Throttle read/write loop
    local throttle_file="$tmp_dir/throttle"
    collect_times "throttle_rw" \
        "cd \"$ROOT_DIR\" && source hooks/lib/throttle.sh && for i in \$(seq 1 100); do throttle_write \"$throttle_file\" 1 1 abc >/dev/null; throttle_read \"$throttle_file\" >/dev/null; done" \
        "$runs" "$tmp_dir/throttle_rw.txt"
    print_stats "throttle_rw" "$tmp_dir/throttle_rw.txt"

    rm -rf "$tmp_dir"
}

if [ -n "$BASELINE_REF" ] && [ "$NO_BASELINE" = "false" ]; then
    if [ -n "$(git status --porcelain)" ]; then
        echo "Warning: working tree has changes; baseline comparison uses a detached worktree." >&2
    fi
    tmp_worktree="$(mktemp -d /tmp/redbull-bench.XXXX)"
    cleanup() {
        git worktree remove -f "$tmp_worktree" >/dev/null 2>&1 || true
        rm -rf "$tmp_worktree"
    }
    trap cleanup EXIT
    git worktree add --detach "$tmp_worktree" "$BASELINE_REF" >/dev/null
    scripts/bench.sh --no-baseline --label "baseline:$BASELINE_REF" --runs "$RUNS" --root "$tmp_worktree" ${SKIP_EVALS:+--skip-evals}
    bench_current_repo "$LABEL" "$RUNS"
    exit 0
fi

bench_current_repo "$LABEL" "$RUNS"
