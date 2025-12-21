<objective>
Consolidate multiple brainstorming/idea files from a specified folder into a single ranked and rated list of ideas. Thoroughly analyze each source file, extract unique ideas, deduplicate similar concepts, score them consistently, and create a comprehensive consolidated document with both summary and detailed sections.
</objective>

<context>
When multiple brainstorming sessions or iterations produce separate idea files, consolidating them into a single ranked list helps prioritize work and avoid duplication. This process synthesizes ideas from multiple sources while preserving all important details and ensuring consistent scoring.

The output will be used for:
- Prioritizing refactoring/feature work
- Creating workplans and epics
- Tracking technical debt and improvements
- Making informed decisions about what to tackle first

### USER INPUT:

ideas = $PROMPT

if ideas is empty, ask the user to provide a path to a folder or the contents of a folder to consolidate.

$PROMPT

</context>

<requirements>
1. **Read all brainstorming files** from the specified folder (typically markdown files with idea lists, scores, and details)

2. **Extract unique ideas** from each file:
   - Identify each distinct idea/concept
   - Note any scoring information (impact, effort, expertise, risk, novelty)
   - Capture implementation details, acceptance criteria, test plans if present
   - Preserve metadata (category, type, area, owner_role, etc.)

3. **Deduplicate and merge** similar ideas:
   - Identify ideas that are essentially the same across files
   - Merge them into a single entry, preserving the most detailed information
   - If scores differ, use the most comprehensive/thoughtful scoring (or average if similar)
   - Combine implementation steps, acceptance criteria, and other details from all sources

4. **Score consistently** using the same criteria:
   - `impact`, `effort`, `expertise`, `risk`, `novelty` are integers 1–5
   - `priority_score` = `round(impact/effort, 2)` (must be calculated consistently)
   - Apply tie-breakers: lower risk → lower expertise → higher impact

5. **Rank by priority score** (highest first)

6. **Create comprehensive consolidated document** with:
   - Focus summary section (purpose, key flows, technical debt indicators, constraints, risks)
   - Summary table with all ideas ranked by priority score
   - Detailed sections for each idea (ticket-ready format with all metadata)
   - Rationale for top 3-5 picks
   - Epics grouping (if applicable)
   - Implementation notes and assumptions

7. **Preserve all details** from originals:
   - Implementation steps
   - Acceptance criteria
   - Test plans
   - Targets/search tokens
   - Expected improvements
   - Current state assessments
   - Any experiment categories, rollback plans, success metrics
</requirements>

<implementation>
1. **Read all files** from the specified folder in parallel to understand scope

2. **Analyze structure** of each file:
   - Identify how ideas are organized (tables, lists, detailed sections)
   - Note scoring methodology used in each
   - Identify any focus summaries or context sections

3. **Extract ideas systematically**:
   - For each file, list all unique ideas with their scores and details
   - Create a master list of all ideas across all files
   - Tag each idea with its source file(s)

4. **Deduplicate intelligently**:
   - Compare idea titles/descriptions for similarity
   - Merge ideas that are essentially the same (e.g., "Extract constants" vs "Extract configuration constants")
   - When merging, preserve:
     - Most detailed implementation steps
     - Most comprehensive acceptance criteria
     - Best/most recent scoring (or synthesize if needed)
     - All unique details from each source

5. **Standardize scoring**:
   - Ensure all scores use the same scale (1-5 integers)
   - Recalculate `priority_score` = `round(impact/effort, 2)` for all entries
   - If scores differ for merged ideas, use the most thoughtful/recent scoring, or average if similar

6. **Rank and organize**:
   - Sort by `priority_score` descending
   - Apply tie-breakers (lower risk → lower expertise → higher impact)
   - Assign sequential IDs (e.g., REF-001, REF-002, etc.)

7. **Create consolidated document**:
   - **Focus Summary**: Synthesize purpose, flows, technical debt, constraints, risks from all sources
   - **Summary Table**: Ranked list with all key metadata columns
   - **Detailed Sections**: Full ticket-ready details for each idea, preserving all original information
   - **Rationale**: Explain why top picks are prioritized
   - **Epics**: Group related ideas into epics if patterns emerge
   - **Notes**: Document assumptions, prerequisites, testing strategy

8. **Verify completeness**:
   - All unique ideas from all sources are included
   - No important details are lost
   - Scoring is consistent throughout
   - Document is well-organized and easy to navigate
</implementation>

<output>
Create a single consolidated markdown file:

Save to: `./docs/ideas/[folder-name]/markdown/consolidated-[descriptive-name].md`

The file should contain:
1. Header with title, generation date, and source attribution
2. Focus Summary section (synthesized from all sources)
3. Consolidated Ideas table (ranked by priority score)
4. Detailed Refactoring Tasks section (ticket-ready format for each idea)
5. Rationale for Top 3-5 section
6. Epics section (if applicable)
7. Implementation Notes section
8. Notes/Assumptions section

Format should match the structure of existing consolidated documents in the codebase, with consistent markdown formatting and clear sections.
</output>

<verification>
Before declaring complete, verify:

1. **Completeness check**:
   - [ ] All ideas from all source files are represented
   - [ ] No duplicate ideas remain (only merged versions)
   - [ ] All detailed information from originals is preserved

2. **Scoring consistency**:
   - [ ] All scores are integers 1-5
   - [ ] All `priority_score` values = `round(impact/effort, 2)`
   - [ ] Ranking follows priority score (highest first)
   - [ ] Tie-breakers are applied correctly

3. **Document quality**:
   - [ ] Focus summary synthesizes information from all sources
   - [ ] Summary table is complete and properly formatted
   - [ ] Detailed sections include all metadata (kind, category, scores, implementation steps, acceptance criteria, test plans, etc.)
   - [ ] Rationale explains top picks clearly
   - [ ] Epics group related ideas logically
   - [ ] Document is well-organized and easy to navigate

4. **Accuracy**:
   - [ ] No information is misrepresented or lost
   - [ ] Merged ideas accurately combine details from all sources
   - [ ] Scores are calculated correctly
</verification>

<success_criteria>
- Single consolidated markdown file created with all ideas ranked by priority
- All unique ideas from all source files are included (no duplicates, all merged)
- All detailed information (implementation steps, acceptance criteria, test plans) is preserved
- Scoring is consistent throughout (same criteria, correct calculations)
- Document structure matches existing consolidated documents
- File is ready for use in prioritization and work planning
</success_criteria>

