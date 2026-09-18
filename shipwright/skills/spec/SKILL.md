---
name: spec
description: Create or update a goal brief — a self-contained development specification card on the brief board. Use when starting a new feature, project, or major change. Interviews the user, produces a trackable brief with requirement IDs and an embedded execution protocol, and outputs a ready-to-paste /goal prompt.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
argument-hint: "[create|update|show] [description of what to build]"
---

# Goal Brief Management

ultrathink

You manage goal briefs — the contract between the human and the execution system. A brief is a Kanban card on the brief board (`briefs/`): its folder location IS its status, it carries its own requirements, execution protocol, task breakdown, progress log, and blockers, and it is the single source of truth for "done."

## The Board

```
briefs/
  1-backlog/    # scoped briefs, not started (multiple OK)
  2-active/     # being executed (WIP limit: exactly 1)
  3-blocked/    # NEEDS HUMAN INTERVENTION — distinct terminal, NOT done
  4-done/       # completed — all requirements verified
```

## Modes

Determine mode from `$ARGUMENTS`:
- Starts with "create" → CREATE mode
- Starts with "update" → UPDATE mode
- Starts with "show" → SHOW mode
- No mode specified → SHOW mode if any briefs exist, otherwise CREATE mode

---

## CREATE Mode

### Step 1: Read the Codebase and Infrastructure Context

Understand what exists before asking questions:
1. Read the project directory structure (`ls` the root, key subdirectories)
2. Read CLAUDE.md for project context. Extract and note:
   - **Architecture**: frontend framework, backend framework, database, deployment platform
   - **Auth**: provider (e.g., Clerk) or none
   - **Design context**: domain, aesthetic direction
   - **Deployment**: platform, URLs, env group
3. `ls briefs/*/` — see what briefs already exist (multiple briefs are fine; each gets its own ID)

These are **infrastructure decisions already made during onboarding.** Do NOT re-ask about them. Focus the interview on PRODUCT decisions.

### Step 2: Interview the Human

Start by acknowledging what you already know from CLAUDE.md:

> "I see this project uses **{frontend}** + **{backend}** + **{database}**, deployed on **{platform}** with **{auth}** for authentication. I won't ask about infrastructure — let's focus on what this product should DO."

Then ask about **product decisions only**:

1. **"What are you building?"** — Get the high-level goal in their words.
2. **"Who is it for?"** — User type, use cases.
3. **"What are the must-have features?"** — These become functional requirements. Ask about user-facing capabilities, not technical implementation.
4. **"What should it NOT do?"** — These become out-of-scope items.
5. **"How will you know it's done?"** — Success criteria.

Ask 1-2 questions at a time, wait for responses, then follow up. Be conversational, not bureaucratic.

**Decomposition-readiness check**: before drafting, ask yourself — could a fresh session break every requirement into subtasks without asking the human anything? If not, ask the follow-up now. Acceptance criteria must be specific and testable (a command output, a visible UI state, a status code — not "works well").

### Step 3: Assign the Brief ID

Find the highest `NNN` prefix across ALL board folders (`ls briefs/*/`), add 1, zero-pad to 3 digits, and append a short slug: `001-user-auth`, `002-reporting`. IDs are permanent and never reused.

### Step 4: Draft the Brief

Write the brief using this EXACT template:

```markdown
---
id: {NNN-slug}
title: "{Title from the goal}"
created: "{ISO 8601 timestamp}"
updated: "{ISO 8601 timestamp}"
completion: 0/{total requirements}
outcome: pending
pending_replan: false
turn_cap: {3 × total requirements + 10}
---

# {Title}

## Overview
{2-3 paragraphs: what is being built, why, who it's for}

## Scope

### In Scope
- {bullet list of what this brief covers}

### Out of Scope
- {bullet list of explicit exclusions}

## Requirements

### Functional Requirements
- [ ] **FR-1**: {Requirement description}
  - Acceptance: {Specific, testable criteria for "done"}
- [ ] **FR-2**: {Next requirement}
  - Acceptance: {criteria}

### Non-Functional Requirements
- [ ] **NFR-1**: {Requirement description}
  - Acceptance: {criteria}

## Technical Constraints
- {constraint 1}
- {constraint 2}

## Success Criteria
{Holistic definition of "done" — beyond individual requirements}

## Execution Protocol

These rules bind ANY session working this brief. The `/orchestrate` skill is the full runner — invoke it if it is not already loaded.

1. **Single writer.** Only the main (orchestrating) session edits this file or moves it between board folders. Subagents never touch it.
2. **Decompose before building.** If Task Breakdown below is empty, fill it before any implementation. Every requirement must map to at least one subtask.
3. **Delegate, don't implement.** Execute each subtask via the matching subagent (frontend-worker / backend-worker / infra-worker). The main session plans, verifies, records, and routes.
4. **Verify before checking.** A requirement checkbox may only be checked when its acceptance criteria are demonstrably met (test output, screenshot, health check in the transcript). Never weaken, reinterpret, or remove a requirement to make it pass.
5. **Park blockers, keep moving.** When a subtask hits a human blocker: record it under `## Blockers` (question + options + empty `Resolution:` line), mark the subtask blocked, and continue every subtask NOT downstream of the blockage (by dependency, file ownership, or shared requirement). Max 3 attempts per subtask; the 3rd failure becomes a blocker.
6. **Document every turn.** Append a Progress Log entry each working turn (a Stop hook enforces this).
7. **Route on terminal state — two DISTINCT outcomes:**
   - **COMPLETE**: all requirement checkboxes checked → set `outcome: completed`, write `## Outcome`, `mv` this file to `briefs/4-done/`, announce "BRIEF COMPLETE".
   - **NEEDS HUMAN**: requirements remain AND zero runnable subtasks → set `outcome: needs-human`, write `## Outcome` listing every open question, `mv` this file to `briefs/3-blocked/`, announce "NEEDS HUMAN INTERVENTION" with the questions. Blocked is NOT done — never present it as completion.
8. **Prove board state.** End every turn by running: `ls briefs/2-active/ briefs/3-blocked/ briefs/4-done/`

## Task Breakdown

_Filled just-in-time by the runner when this brief becomes active. Current phase in detail; future phases as placeholder rows._

| ID | Phase | Description | Agent | Requirements | Depends On | Files Owned | Status | Attempts |
|----|-------|-------------|-------|--------------|------------|-------------|--------|----------|

## Progress Log

_Append-only. One entry per working turn: timestamp, what happened, what's next._

## Blockers

_None yet. Each blocker gets: title, type, description, context, options, and an empty `Resolution:` line for the human._

## Outcome

_Written when this brief is routed out of 2-active/. States which terminal (completed / needs-human) and why._
```

### Step 5: Present and Confirm

Show the drafted brief to the human. Ask: "Does this capture what you want to build? Any requirements to add, remove, or change?"

Iterate until the human approves.

### Step 6: Write to Disk and Output the Goal Prompt

1. `mkdir -p briefs/1-backlog briefs/2-active briefs/3-blocked briefs/4-done session/{brief-id}`
2. Write the approved brief to `briefs/1-backlog/{brief-id}.md`
3. Initialize `session/{brief-id}/trajectory.md`:
   ```markdown
   # Trajectory — {title}
   Brief: {brief-id} — {N} requirements
   Started: {ISO timestamp}
   ```
   Then append SPEC_START (the user's initial description), SPEC_INTERVIEW (questions and answers), and SPEC_APPROVED (requirement count) events in this format:
   ```markdown
   ---

   ### Step — | {ISO timestamp} | SPEC_SKILL | {ACTION_TYPE}
   **Action:** {what happened}
   **Input:** {question asked or user's request}
   **Output:** {user's response or spec content}
   ```
4. Tell the human, filling in every placeholder:

````
Brief created: briefs/1-backlog/{brief-id}.md

To run it autonomously, paste this goal (it starts working immediately and
keeps going until the brief reaches a terminal folder):

/goal Brief {brief-id} ("{title}") is in a terminal folder: briefs/4-done/ or briefs/3-blocked/. These are DISTINCT terminals. (A) COMPLETE — the brief is in briefs/4-done/ with every requirement checkbox checked, each verified against its acceptance criteria. (B) NEEDS HUMAN INTERVENTION — the brief is in briefs/3-blocked/, legitimate ONLY after every runnable subtask finished and every blocker is documented with options and an empty "Resolution:" line; the final turn must announce "NEEDS HUMAN INTERVENTION" with the open questions and must NOT claim success. Work the brief per its Execution Protocol section (invoke /orchestrate to start). Never weaken or remove requirements, never check a box without verified acceptance, never route to blocked while runnable work remains. Prove board state every turn by running: ls briefs/2-active/ briefs/3-blocked/ briefs/4-done/. Safety: stop after {turn_cap} turns and report remaining work.

Or run it manually, one turn at a time, with /orchestrate.
Check progress anytime with /status.
````

---

## UPDATE Mode

### Step 1: Locate the Brief
`$ARGUMENTS` may name a brief ID; otherwise use the single brief in `2-active/`, or ask which brief to update. Find it via `ls briefs/*/`.

- Brief in `4-done/`: do NOT reopen it. Tell the human that done is terminal — new work gets a new brief (offer to create one referencing the old).
- Brief in `1-backlog/`, `2-active/`, or `3-blocked/`: proceed.

### Step 2: Accept Changes
The human describes what to change. Apply these rules:

- **Adding requirements**: Use the next available ID. If FR-1 through FR-5 exist, new one is FR-6. NEVER reuse a removed ID.
- **Removing requirements**: Delete the requirement line entirely. Do NOT renumber other requirements. Mark any pending subtasks for it as cancelled in the Task Breakdown.
- **Modifying requirements**: Update the description/acceptance in place. Keep the same ID.
- **Changing scope**: Update the In Scope / Out of Scope sections.

### Step 3: Update Frontmatter and Log
- Set `updated` to current timestamp; update the `completion` denominator; recompute `turn_cap`
- If the brief is in `2-active/`: set `pending_replan: true` — the runner re-plans on its next turn
- Append a Progress Log entry: "Brief updated by human: {summary of changes}"

Tell the human: "Brief updated." If it was in `3-blocked/` and the change resolves the blockage, remind them: "Run /orchestrate to resume it."

---

## SHOW Mode

Render the board:

```
== BRIEF BOARD ==
1-backlog:  {count}  {list of "id — title"}
2-active:   {count}  {id — title, completion, current phase}
3-blocked:  {count}  {list of "id — title (N open questions)"}  ← NEEDS HUMAN
4-done:     {count}  {list of "id — title"}
```

If a brief ID is given in `$ARGUMENTS`, also show that brief's requirements with checkboxes, task breakdown status, open blockers, and last 3 progress entries. If a blocked brief has open questions, print them in full — that is the human's to-do list.

---

## Rules

- Requirement IDs are PERMANENT. Never reuse, never renumber.
- The spec skill writes briefs ONLY to `1-backlog/` (create) or edits them in place (update). It NEVER moves briefs between folders — that is the runner's job.
- The spec skill NEVER fills the Task Breakdown or checks requirement checkboxes.
- `3-blocked/` and `4-done/` are different terminals. Never describe a blocked brief as complete.

$ARGUMENTS
