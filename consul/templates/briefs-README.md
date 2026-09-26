# Brief Board

This directory is a Kanban board for goal briefs. **Folder location IS status** — the brief file is the card and it moves; nothing else does.

```
1-backlog/    scoped briefs, not started (any number)
2-active/     being executed right now (never more than 1)
3-blocked/    NEEDS HUMAN INTERVENTION — a distinct terminal, NOT done
4-done/       completed — every requirement verified
```

Each brief is self-contained: requirements with acceptance criteria, an embedded Execution Protocol, a Task Breakdown, an append-only Progress Log, Blockers with `Resolution:` lines, and an Outcome. Reading the file tells you everything without digging into `session/` (which holds gitignored machine state per brief: trajectory logs).

## Workflow

1. `/spec create "what you want"` → interview → brief lands in `1-backlog/`, and you get a ready-to-paste `/goal` prompt.
2. Paste the `/goal` prompt (autonomous — keeps working until the brief reaches a terminal folder), or run `/orchestrate` manually one turn at a time.
3. The runner moves the brief to `2-active/`, decomposes it, delegates subtasks to worker subagents, and updates the brief as it goes.
4. Terminal routing — two DIFFERENT outcomes:
   - **`4-done/`** — all requirements checked and verified. Complete.
   - **`3-blocked/`** — the runner did everything it could, and what remains needs YOU. Open the brief, read `## Outcome` and `## Blockers`, write your answers on the `Resolution:` lines, then run `/orchestrate` to resume.
5. `/status` shows the board at any time. `/spec update {id}` changes a brief's requirements.

## Rules

- Only the runner (main Claude session) edits briefs or moves them between folders. Worker subagents never touch them. Humans edit only `Resolution:` lines and `/spec update` changes.
- Requirement IDs (FR-n / NFR-n) are permanent — never reused or renumbered.
- A brief in `3-blocked/` is never "done." A brief in `4-done/` is never reopened — follow-up work gets a new brief.
