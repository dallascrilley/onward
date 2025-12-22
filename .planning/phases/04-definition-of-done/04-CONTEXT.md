# Phase 4: Definition of Done - Context

**Gathered:** 2025-12-22
**Status:** Ready for research

<vision>
## How This Should Work

Users define project-specific completion rules in `.claude/redbull.local.md` using YAML frontmatter. These rules describe what "done" looks like for their project — not as a checklist to validate, but as context hints that get injected into the judge's prompt.

The judge uses these hints to shift its reasoning boundary. When a user says "always run tests before stopping," the judge weighs that against the current context when deciding continue vs stop.

Two modes:
- **Advisory mode** (default): Rules inform the judge's decision as additional context
- **Strict mode**: Hard-fail if criteria appear unmet (stronger bias in prompt)

The key is that rules actually change decisions, not just exist as configuration. A perfectly parsed rule that doesn't affect outcomes is wasted complexity.

</vision>

<essential>
## What Must Be Nailed

- **Judge integration**: Rules must meaningfully influence the judge's stop/continue decisions. This is the only thing that matters. If DoD doesn't change behavior, Phase 4 fails.
- **Observable differences**: Clear, measurable difference in decisions with/without DoD rules present

</essential>

<boundaries>
## What's Out of Scope

- **Automatic rule inference**: No detecting rules from codebase — users must define them explicitly
- **Multi-file configs**: Single config file only — no per-directory or inherited rules
- **Soft preferences**: Only hard rules — no "I prefer" style guidance (save for future tuning)
- **Complex schemas**: Rule parsing can be simple (YAML frontmatter + list of strings); polish comes later
- **Authoring UX**: Users can refine config format in future iterations

</boundaries>

<specifics>
## Specific Ideas

- **Config format**: YAML frontmatter in `.claude/redbull.local.md` — structured DoD hints with natural-language authoring preserved
- **Rule types (in priority order)**:
  1. Project-specific rules (highest ROI): "Always run tests before stopping", "Never stop mid-refactor", "Docs + changelog required before stop", "No TODOs allowed at completion"
  2. Task-type awareness (secondary): "Features require tests", "Bug fixes require repro + verification" — best as guidance, not enforcement
- **Focus on prompt injection**: Clear, unambiguous injection into judge prompt; strong bias in strict mode

</specifics>

<notes>
## Additional Context

Phase 4 is about changing decisions, not configuration elegance.

The judge is the only decision authority in Phase 4. DoD exists solely to shift the judge's reasoning boundary. Everything else (schema polish, UX, validation) is secondary to making rules actually affect outcomes.

Practical success criteria: Can we demonstrate that adding a DoD rule changes a scenario's decision from stop → continue (or vice versa)?

</notes>

---

*Phase: 04-definition-of-done*
*Context gathered: 2025-12-22*
