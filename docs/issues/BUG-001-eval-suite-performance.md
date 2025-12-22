# BUG-001: Eval Suite Takes 10+ Minutes Due to Real API Calls

## Summary

The eval harness (`test/evals/run-evals.sh`) makes **325 real Claude Haiku API calls**, causing each eval run to take 10-30+ minutes. This makes the quality gate impractical for development iteration.

## Root Cause

```
65 scenarios × 5 runs each × 1 Claude API call per run = 325 API calls
```

Each API call takes 1-5+ seconds depending on network latency and API load.

**Call path:**
```
run-evals.sh (line 76)
  └─ hooks/claude-judge-continuation.sh (line 136)
       └─ claude --print --model haiku ... ← REAL API CALL
```

## Impact

- **Quality gates unusable:** REF-011 (and all refactors) require `./test/evals/run-evals.sh` as proving command
- **Dev velocity:** 10-30 min wait per change makes iteration slow
- **CI/CD costs:** 325 API calls per run × multiple PRs = significant API usage
- **Flakiness risk:** Real API calls can timeout/fail, causing false negatives

## Reproduction

```bash
time ./test/evals/run-evals.sh
# Expected: 10-30+ minutes
```

## Proposed Solutions (Pick One)

### Option A: Mock Mode for Eval Suite (Recommended)

Add `EVAL_MOCK_MODE=true` environment variable that replaces the Claude call with deterministic responses based on transcript hashing:

```bash
# In hook script
if [ "$EVAL_MOCK_MODE" = "true" ]; then
    # Return deterministic decision based on transcript content
    # e.g., hash transcript → lookup precomputed decision
fi
```

**Pros:** Fast (<10 seconds), deterministic, no API costs
**Cons:** Doesn't test real Claude behavior, requires maintaining mock decisions

### Option B: Reduce Runs Per Scenario

Make the 5 runs per scenario configurable:

```bash
RUNS_PER_SCENARIO=${RUNS_PER_SCENARIO:-5}
for run in $(seq 1 $RUNS_PER_SCENARIO); do
```

**Usage:** `RUNS_PER_SCENARIO=1 ./test/evals/run-evals.sh`

**Pros:** 5× faster with single run
**Cons:** Still makes 65 API calls (~2-5 minutes), loses reliability signal

### Option C: Parallel Execution

Run scenarios in parallel with GNU parallel or background jobs:

```bash
run_scenario() { ... }
export -f run_scenario
parallel -j 10 run_scenario ::: "$SCENARIOS_DIR"/*.json
```

**Pros:** ~10× faster with parallelism
**Cons:** Still makes 325 API calls (just faster), potential rate limiting

### Option D: Cached Responses

Cache Claude responses keyed by transcript hash:

```bash
CACHE_KEY=$(echo "$RECENT_CONTEXT" | md5sum | cut -d' ' -f1)
CACHE_FILE="/tmp/hook-cache/$CACHE_KEY.json"
if [ -f "$CACHE_FILE" ]; then
    CLAUDE_RESPONSE=$(cat "$CACHE_FILE")
else
    CLAUDE_RESPONSE=$(...claude call...)
    echo "$CLAUDE_RESPONSE" > "$CACHE_FILE"
fi
```

**Pros:** Subsequent runs are instant
**Cons:** First run still slow, cache invalidation complexity

## Recommendation

Implement **Option A (Mock Mode)** for unit testing with **Option B (configurable runs)** for integration testing:

- Dev workflow: `EVAL_MOCK_MODE=true ./test/evals/run-evals.sh` (~10 seconds)
- CI integration: `RUNS_PER_SCENARIO=1 ./test/evals/run-evals.sh` (~2-5 minutes)
- Full validation: `./test/evals/run-evals.sh` (~10-30 minutes, nightly or pre-release)

## Workaround (Immediate)

For now, developers can run a subset of scenarios:

```bash
# Test single scenario
echo '{"session_id":"test","transcript_path":"/tmp/test.json"}' | ./hooks/claude-judge-continuation.sh

# Or move most scenarios temporarily
mkdir test/evals/scenarios-full
mv test/evals/scenarios/[2-6]*.json test/evals/scenarios-full/
./test/evals/run-evals.sh  # Only ~10 scenarios
```

## Related

- REF-011: Blocked by inability to run proving command quickly
- All other refactors: Same issue
