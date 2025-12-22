# Phase 4: Definition of Done (DoD) Support

**Date:** 2025-12-22
**Status:** Design
**Depends On:** Phase 2 (v2 schema) + Phase 3 (heuristics, optional)

---
## Executive Summary

**Phase 4 introduces a user-defined Definition of Done (DoD)** that the judge must consider when deciding whether to allow stopping.  
DoD is loaded from project config and injected into the judge prompt. Users can choose:
- **Advisory** (default): DoD informs the judge, but judge can still stop.
- **Strict**: judge should not stop unless DoD is plausibly met or an unresolvable blocker exists.

## Problem

Claude’s notion of “done” often differs from the user’s:
- tests not run
- TODOs remain
- docs/changelog missing
- acceptance criteria not verified

Without explicit criteria, the judge can approve stop prematurely.

## Purpose

- Align stop decisions with explicit user intent.
- Reduce “sounds done” false stops by making completion criteria explicit.
- Provide a configurable strictness level per project.

## What This Phase Does

- Adds DoD parsing from a project config frontmatter section.
- Injects DoD into the judge prompt with clear evaluation instructions.
- Adds strict mode behavior where uncertainty biases toward continuing unless blocked.
- Extends explain output to show DoD mode applied (optional but recommended).

## What This Phase Does NOT Do

- Does not automatically run tests / lint / typecheck.
- Does not inspect git diff or filesystem for proof (beyond what the assistant states).
- Does not hard-block stopping at the hook layer (unless future “enforcement” is added).

## Success Criteria

**Correctness**
- DoD parsed reliably (including empty/no config case).
- Existing scenarios unaffected when no DoD configured.
- New DoD scenarios pass 5/5.

**Behavior**
- Advisory mode: judge incorporates DoD but may stop if reasonable.
- Strict mode: judge refuses to stop unless:
  1) DoD is explicitly met with evidence, or
  2) there is a genuine blocker requiring the user.

**User Value**
- Fewer premature stops on projects that require tests/docs/acceptance checks.

## Rollout / Safety Notes

- If DoD parsing fails, treat as “no DoD” (graceful).
- Strict mode must bias toward CONTINUE on uncertainty (to avoid premature stop).
- Combine with stall detection later to avoid looping when DoD is vague.

## Goal

Align stop decisions with **user intent**, not assistant tone. Stop only when the user considers work done, allowing judge to be strict about completion criteria.

**Problem it solves:** Assistant sounds "done" but user hasn't verified tests pass, docs are written, or all acceptance criteria are met.

---

## Current State

- Judge asks: "Does assistant have more autonomous work to do?"
- Decision: STOP if work sounds complete
- **Gap:** Judge doesn't know what "done" means to the user (acceptance criteria, test coverage, DoD, etc.)

---

## Phase 4 Design: User-Defined Definition of Done

### Configuration: Where DoD Lives

**Option A (Chosen):** Extend `.claude/redbull.local.md` frontmatter

```markdown
---
version: "1.0"
enabled: true
aggressiveness: medium
definition_of_done:
  - "All tests pass (npm test shows 0 failures)"
  - "No TODO comments in code"
  - "Updated CHANGELOG.md"
  - "Type checking passes (pnpm typecheck)"
---

# Per-Project Redbull Configuration
```

**Why:** Colocated with other project settings; simple YAML; no new file format.

### Scope Gate: Enforcement Level

**Decision:** Default to **advisory** (inform judge), upgrade to **strict** on user request.

| Level | Behavior |
|-------|----------|
| **Advisory** (default) | Judge knows DoD exists; uses it to inform decision but can override |
| **Strict** | Judge refuses to stop until DoD is plausibly met |
| **Enforcement** (future) | Hook rejects stop if DoD not met, regardless of judge |

For Phase 4, implement **advisory + strict** (user chooses via `enforcement: strict`).

### Implementation: Three Files

#### 1. `hooks/lib/settings.sh` — Parse DoD

**Add after existing settings parsing (around line 30):**

```bash
# Load Definition of Done from project config
load_definition_of_done() {
    local config_file="${REDBULL_CONFIG_FILE:-${CLAUDE_WORK_DIR}/.redbull/redbull.local.md}"

    # Default: no DoD
    DEFINITION_OF_DONE=""
    DOD_ENFORCEMENT="advisory"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    # Extract YAML frontmatter (between --- markers)
    local frontmatter
    frontmatter=$(awk '/^---$/{if(++count==1){flag=1;next}; if(count==2){flag=0}} flag' "$config_file")

    # Parse definition_of_done array
    if echo "$frontmatter" | grep -q "definition_of_done:"; then
        # Extract lines until next top-level key or end
        DEFINITION_OF_DONE=$(echo "$frontmatter" | \
            awk '/definition_of_done:/{flag=1; next} /^[a-z_]+:/{if(flag)exit} flag' | \
            sed 's/^[[:space:]]*-[[:space:]]*//')
    fi

    # Parse enforcement level
    if echo "$frontmatter" | grep -q "dod_enforcement: strict"; then
        DOD_ENFORCEMENT="strict"
    fi
}

# Export for use in judge
export DEFINITION_OF_DONE
export DOD_ENFORCEMENT
```

#### 2. `hooks/lib/prompt.sh` — Inject DoD Into Prompt

**Modify `build_evaluation_prompt_with_rules()` (via DoD section) to include DoD guidance:**

```bash
build_evaluation_prompt() {
    local context="$1"
    cat <<EOF
Analyze this conversation and determine: Does the assistant have more autonomous work to do RIGHT NOW?

Conversation:
$context

CONTINUE (should_continue: true) ONLY IF the assistant explicitly states what it will do next:
... (existing rules) ...

STOP (should_continue: false) in ALL other cases:
... (existing rules) ...

$([ -n "$DEFINITION_OF_DONE" ] && cat <<'DOD_SECTION'
---
DEFINITION OF DONE

The user has defined these completion criteria. When evaluating whether work is done, consider:
DOD_SECTION
echo "$DEFINITION_OF_DONE" | sed 's/^/- /'
[ "$DOD_ENFORCEMENT" = "strict" ] && cat <<'STRICT_SECTION'

STRICT MODE: Only approve STOP if the assistant has:
1. Explicitly stated all DoD criteria are met, OR
2. Provided evidence (test output, verification, etc.) that DoD is satisfied, OR
3. Hit an unresolvable blocker

If DoD is unclear or only partially met, bias toward CONTINUE.
STRICT_SECTION
[ "$DOD_ENFORCEMENT" != "strict" ] && cat <<'ADVISORY_SECTION'

ADVISORY MODE: Default to STOP when uncertain.
ADVISORY_SECTION
)
EOF
}
```

#### 3. `hooks/claude-judge-continuation.sh` — Load DoD at Runtime

**Add after settings loading (line ~75):**

```bash
# Load definition of done if available
source "$SCRIPT_DIR/lib/settings.sh"
load_definition_of_done
```

### Test Scenarios (10 New Files, 91–100)

Each tests DoD interaction:

- **91:** No DoD configured → judge uses default rules
- **92:** DoD: "tests pass" + assistant says "tests pass" → stop
- **93:** DoD: "tests pass" + assistant says "done" but no test output → continue (strict mode)
- **94:** DoD: multiple criteria → stop when all listed
- **95:** DoD advisory mode: work incomplete but no explicit criteria → judge can still stop
- **96:** DoD strict mode: partial completion → force continue
- **97:** DoD with blockers: unresolvable error → stop despite incomplete DoD
- **98:** False positive guard: "tests pass" string appears but not actually verified
- **99:** DoD with acceptance criteria: verify assistant addressed all
- **100:** Dynamic DoD: changes between sessions (config update)

### Acceptance Criteria

- [ ] DoD parsed from `.claude/redbull.local.md` frontmatter correctly
- [ ] Judge receives DoD context and incorporates into decision
- [ ] Advisory mode: judge considers DoD but can override
- [ ] Strict mode: judge refuses to stop until DoD plausibly met
- [ ] All 10 new scenarios pass 5/5 runs
- [ ] All 96 previous scenarios still pass (total: 106)
- [ ] `explain.sh --verbose` shows whether DoD applied
- [ ] Missing DoD = unchanged behavior from Phase 3

### Proving Command

```bash
./test/evals/run-evals.sh

# Test DoD parsing:
source hooks/lib/settings.sh
REDBULL_CONFIG_FILE="test/fixtures/dod-config.md" load_definition_of_done
echo "$DEFINITION_OF_DONE"
```

### Files to Modify

| File | Change | Why |
|------|--------|-----|
| `hooks/lib/settings.sh` | Add `load_definition_of_done()` | Parse DoD from config |
| `hooks/lib/prompt.sh` | Modify `build_evaluation_prompt_with_rules()` | Inject DoD into prompt |
| `hooks/claude-judge-continuation.sh` | Call `load_definition_of_done()` | Load config at runtime |
| `.claude/redbull.local.md` (example) | Document DoD field | Config documentation |
| `test/evals/scenarios/` | Add 10 new scenarios (91–100) | Test DoD logic |
| `README.md` | Document DoD feature | User-facing docs |

### DoD Format Examples

**Minimal:**
```markdown
---
definition_of_done:
  - "All tests pass"
---
```

**Comprehensive:**
```markdown
---
definition_of_done:
  - "npm test shows 0 failures"
  - "npm run typecheck passes"
  - "No TODO comments remain"
  - "CHANGELOG.md updated"
  - "git log shows all commits squashed"
dod_enforcement: strict
---
```

### How Judge Uses DoD

**Advisory Mode (Default):**
```
Judge sees:
  - DoD: "tests pass, no TODOs"
  - Transcript: "I've added tests but haven't cleaned up TODOs"

Decision: Can stop (advisory) OR continue (to clean up)
          Judge uses reasoning to decide which
```

**Strict Mode:**
```
Judge sees:
  - DoD: "tests pass, no TODOs"
  - Transcript: "I've added tests but haven't cleaned up TODOs"

Decision: Must continue (DoD not met)
          Judge refuses to stop
```

### Risk & Mitigations

| Risk | Mitigation |
|------|-----------|
| User forgets to configure DoD | Defaults to advisory (no breaking change) |
| DoD criteria are vague | Judge uses reasoning to interpret |
| Assistant claims DoD is met without proof | Strict mode requires evidence |
| Config parsing fails | Fall back to no DoD (graceful) |
| DoD encourages infinite loops | Combine with Phase 5 stall detection |

### How Phase 4 Builds on Earlier Phases

- **Phase 2:** Uses v2 schema fields to assess DoD progress (confidence, decision_category)
- **Phase 3:** DoD works with heuristics (e.g., "asking_for_approval" → check DoD before stopping)
- **Phase 5:** Stall detection considers whether loop is due to DoD not being met

---

## Implementation Order

1. **Add DoD parsing** → `hooks/lib/settings.sh`
2. **Inject into prompt** → `hooks/lib/judge.sh`
3. **Load at runtime** → `hooks/claude-judge-continuation.sh`
4. **Add test scenarios** → `test/evals/scenarios/91-100`
5. **Document** → README.md + example config

---

## Configuration Reference

### `.claude/redbull.local.md` Frontmatter

```yaml
---
version: "1.0"
enabled: true
aggressiveness: medium              # low|medium|high (context window size)
dod_enforcement: strict             # advisory|strict (how strictly judge enforces DoD)
definition_of_done:
  - "Criterion 1"
  - "Criterion 2"
  - "Criterion 3"
---
```

### Criterion Examples

```yaml
definition_of_done:
  # Testing
  - "npm test passes (0 failures)"
  - "npm run coverage shows >80% coverage"

  # Code quality
  - "No TODO or FIXME comments"
  - "npm run typecheck passes"
  - "npm run lint passes"

  # Documentation
  - "README.md updated for new features"
  - "CHANGELOG.md has entry for this task"
  - "API documentation generated"

  # Deployment
  - "git commit is ready for production"
  - "Docker image builds successfully"
  - "Migrations run without errors"

  # Acceptance
  - "All acceptance criteria from PR met"
  - "Design review approved"
  - "Security audit passed"
```

---

## Glossary

- **Definition of Done (DoD):** User-defined checklist for completion
- **Advisory Mode:** Judge considers DoD but can override
- **Strict Mode:** Judge refuses to stop until DoD is met
- **DoD Enforcement:** Level of strictness (advisory vs strict)
- **Frontmatter:** YAML metadata in markdown file headers
