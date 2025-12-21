# REF-001: Repair Eval Harness Hook Script Path

**Kind**: Improvement
**Category**: Conventional
**Type**: Testing
**Area**: Build
**Priority Score**: 5.00

---

## Problem Statement

The eval harness (`test/evals/run-evals.sh`) references a non-existent path:
```bash
HOOK_SCRIPT="$SCRIPT_DIR/../../scripts/claude-judge-continuation.sh"
```

The actual hook script lives at:
```
hooks/claude-judge-continuation.sh
```

### Impact

When the hook script cannot be found, the harness falls back to:
```bash
hook_output=$(echo "$hook_event" | "$HOOK_SCRIPT" 2>/dev/null || echo '{"decision": "error"}')
```

This `{"decision": "error"}` is then interpreted as `should_continue=false` (STOP), causing:
- Scenarios expecting STOP to "pass" incorrectly
- Regressions to go undetected
- False confidence in test results

---

## Implementation Phase

**Type**: Testing Infrastructure
**Estimated**: 30 minutes
**Files**: 2 files (test/evals/run-evals.sh, RELENG.md)

### Tasks

- [ ] **Fix hook script path** in `test/evals/run-evals.sh` line 10
  - Change: `../../scripts/...` → `../../hooks/...`

- [ ] **Add preflight validation** after line 11
  - Check `HOOK_SCRIPT` exists and is executable
  - Fail fast with clear error if not found

- [ ] **Fix error masking** at line 70
  - Hook execution failures should fail the scenario run
  - Not silently map to `{"decision": "error"}` which passes STOP scenarios

- [ ] **Update RELENG.md** references (lines 86, 90, 100)
  - Change `./scripts/claude-judge-continuation.sh` → `./hooks/claude-judge-continuation.sh`
  - Line 100 checklist item: `scripts/...` → `hooks/...`

### Code Changes

#### 1. Fix path (run-evals.sh line 10)
```bash
# Before
HOOK_SCRIPT="$SCRIPT_DIR/../../scripts/claude-judge-continuation.sh"

# After
HOOK_SCRIPT="$SCRIPT_DIR/../../hooks/claude-judge-continuation.sh"
```

#### 2. Add preflight check (after line 11)
```bash
# Validate hook script exists
if [ ! -x "$HOOK_SCRIPT" ]; then
    echo -e "${RED}ERROR: Hook script not found or not executable: $HOOK_SCRIPT${NC}" >&2
    exit 1
fi
```

#### 3. Fix error masking (line 70)
```bash
# Before: silently converts failures to "error" decision
hook_output=$(echo "$hook_event" | "$HOOK_SCRIPT" 2>/dev/null || echo '{"decision": "error"}')

# After: capture exit code and fail explicitly on execution errors
hook_output=$(echo "$hook_event" | "$HOOK_SCRIPT" 2>&1)
hook_exit_code=$?
if [ $hook_exit_code -ne 0 ]; then
    echo -e "   ${RED}✗${NC} Run $run: HOOK EXECUTION FAILED (exit code: $hook_exit_code)"
    echo "      Output: $hook_output"
    fails=$((fails + 1))
    continue
fi

# Validate JSON response
if ! echo "$hook_output" | jq -e '.decision' >/dev/null 2>&1; then
    echo -e "   ${RED}✗${NC} Run $run: INVALID HOOK RESPONSE (not valid JSON with decision)"
    echo "      Output: $hook_output"
    fails=$((fails + 1))
    continue
fi
```

#### 4. RELENG.md updates
```markdown
# Lines 86, 90: Change example commands
./hooks/claude-judge-continuation.sh

# Line 100: Update checklist item
- [ ] `hooks/claude-judge-continuation.sh` - executable, correct logic
```

---

## Verification Criteria

- [ ] Running `./test/evals/run-evals.sh` with wrong path fails immediately with clear error
- [ ] Running `./test/evals/run-evals.sh` with correct path executes scenarios
- [ ] Hook execution failures (non-zero exit) fail the scenario run explicitly
- [ ] Invalid JSON responses fail the scenario run explicitly
- [ ] RELENG.md examples use `./hooks/` path
- [ ] Hook script itself is NOT modified (verify: `git diff hooks/` shows no changes)

---

## Exit Criteria

1. `./test/evals/run-evals.sh` runs successfully against real hook
2. Preflight check catches missing/non-executable hook script
3. Execution failures are surfaced, not masked
4. Documentation paths are consistent with actual structure

---

## Proving Commands

```bash
# 1. Verify preflight catches bad path (temporarily break it)
sed -i.bak 's|hooks/claude|WRONG/claude|' test/evals/run-evals.sh
./test/evals/run-evals.sh  # Should fail immediately
mv test/evals/run-evals.sh.bak test/evals/run-evals.sh  # Restore

# 2. Run full eval suite
./test/evals/run-evals.sh

# 3. Verify hook not modified
git diff hooks/
```

---

## Notes

- This is a **confidence-restoring** fix that enables future refactoring work
- Scenario expectations remain unchanged; only harness behavior is fixed
- The 29/65 false passes observed were all STOP scenarios passing due to error masking
