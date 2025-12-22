# Phase 1: Permission Prefilter - Context

**Gathered:** 2025-12-22
**Status:** Ready for planning

<vision>
## How This Should Work

When Claude stops, before calling the expensive judge, we check the last assistant message for obvious permission-seeking language. Two tiers:

1. **Permission-seeking** ("Should I continue?", "Shall I proceed?", "Is it OK if I...?") → BLOCK stop, work continues. The assistant is just being polite; obvious answer is "yes, continue."

2. **Needs user choice** (explicit decision requests like "Which approach do you prefer?", approval requests like "Does this look good?", or optional work with explicit framing like "(optional)" or "(nice to have)") → APPROVE stop, wait for user.

Everything ambiguous falls through to judge unchanged. This is cheap (regex on one message) and deterministic (no LLM calls). Conservative by design: only match what we're 100% confident about.

</vision>

<essential>
## What Must Be Nailed

- **Zero false positives** - If there's any doubt, fall back to judge. Never incorrectly stop or continue based on pattern matching. Ambiguous cases must go to judge.
- **High precision matching** - Require question mark, require full phrase context, require explicit optional framing for "want me to" / "should I also" patterns.
- **Conservative fallback** - If pattern extraction fails, message parsing fails, or no pattern matches → judge handles it (unchanged behavior).

</essential>

<boundaries>
## What's Out of Scope

- No confidence scoring or weighting (that's Phase 3)
- No multi-message context reasoning - only inspect last assistant message
- No changes to judge prompt or schema (that's Phase 2)
- No new config options - no YAML settings, no "aggressiveness" knobs
- No new persistence or log formats (debug logs are fine)
- No "soft prompt" behavior - no nudges, no staged escalation
- No broad "needs user choice" expansion - only stop on very explicit decision/approval requests

</boundaries>

<specifics>
## Specific Ideas

- Require question mark in last message (high precision guard)
- "want me to" and "should I also" only approve when combined with explicit optional framing ("optional", "nice-to-have", "if you want") - without framing, fall back to judge
- Pattern matching lives in `hooks/lib/judge.sh` as new functions
- Integration point: between existing ignore patterns and judge call
- Debug logs must clearly show "permission_language" path vs "judge" path
- 5-10 new test scenarios covering permission-seeking, user-choice, and edge cases
- Target ~0 false positives in eval suite; ~5-15% judge call reduction

</specifics>

<notes>
## Additional Context

Design doc already exists at `docs/plans/design/2025-12-22-phase1-design.md` with implementation details, regex patterns, and test scenario ideas.

Key philosophy: This is a foundational phase designed to ship immediately. It's intentionally conservative to avoid regressions. Later phases (especially Phase 3) will do more sophisticated pattern detection using structured signals.

Phase 1 linguistic detection + Phase 3 structured detection = complementary, not redundant. Phase 1 catches the obvious cases fast; Phase 3 confirms or refines using richer signals.

</notes>

---

*Phase: 01-permission-prefilter*
*Context gathered: 2025-12-22*
