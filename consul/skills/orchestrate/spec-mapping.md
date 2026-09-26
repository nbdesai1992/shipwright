# Spec-to-Phase-to-Task Mapping

How to decompose a spec into phases and map requirements to tasks.

## The Mapping Hierarchy

```
Spec Requirement (FR-1)
    → Phase (phase-2: API Layer)
        → Task (p2-task-1: Create registration endpoint)
        → Task (p2-task-3: Write registration tests)
```

One requirement can map to multiple tasks across one or more phases.
One task can advance multiple requirements.

## Phase Generation Rules

### Rule 1: Dependency-Driven Boundaries
Phases align with integration points. The canonical order for a full-stack feature:

1. **Data Layer** — Models, migrations, database setup
2. **API Layer** — Endpoints, business logic, authentication
3. **Frontend** — UI components, wiring to API
4. **Integration & Deploy** — End-to-end verification, deployment

Not every spec needs all four. A frontend-only change is a single phase. A backend-only feature skips phase 3.

### Rule 2: Phase Size
Each phase should be completable in one orchestrator turn: 3-8 tasks. If a phase would have more than 8 tasks, split it into sub-phases.

### Rule 3: Just-in-Time Decomposition
Only decompose the CURRENT phase into detailed subtasks. Future phases get one placeholder row in the Task Breakdown:
- A name and objective
- The requirements they'll cover

This prevents stale plans. The world changes as work progresses — schemas evolve, APIs take unexpected shapes. Decomposing later uses the latest information.

## Requirement Coverage Validation

After decomposition, verify:

1. **Every FR-* and NFR-* has at least one task assigned** (across all phases, including future phases at the high level).
2. **No requirement is orphaned** — if a requirement maps to a future phase that hasn't been decomposed yet, that's fine. But it must be listed in that phase's `requirements` field.

If a requirement can't be mapped to any phase, it may be:
- Out of scope (update the spec)
- A meta-requirement that's verified during integration (assign to the final phase)
- Unclear (raise a blocker to the human)

## Cross-Phase File Ownership

### Within a phase: STRICT exclusivity
No two tasks in the same phase touch the same file. If they need to, merge them into one task.

### Across phases: Managed handoff
The same file CAN be touched by tasks in different phases (phases are sequential, not parallel). Use setup tasks for shared config:

```
p1-task-0-setup: Creates backend/config.py, .env
p2-task-0-setup: Extends backend/config.py with API settings (inherits from p1-task-0-setup)
```

Note the inheritance in the subtask's Depends On column so the runner passes the prior subtask's interface contracts in the spawn prompt.

## Example: Full-Stack Feature Mapping

Spec: "User Profile Management"

```
FR-1: Users can create an account     → phase-1 (model), phase-2 (endpoint), phase-3 (UI form)
FR-2: Users can view their profile    → phase-2 (endpoint), phase-3 (profile page)
FR-3: Users can update preferences    → phase-1 (model field), phase-2 (endpoint), phase-3 (settings UI)
NFR-1: API < 200ms response           → phase-2 (indexing), phase-4 (load test verification)
NFR-2: Accessible UI                  → phase-3 (ARIA, keyboard nav), phase-4 (accessibility audit)
```

Phase 1 tasks:
- p1-task-1: User model (advances FR-1, FR-3)
- p1-task-2: Migration script (advances FR-1)
- p1-task-3: Model tests (advances FR-1)

Phase 2 tasks (decomposed after phase 1 completes):
- p2-task-1: POST /api/users endpoint (advances FR-1, FR-3)
- p2-task-2: GET /api/users/:id endpoint (advances FR-2)
- p2-task-3: Database indexes for performance (advances NFR-1)
- p2-task-4: API tests (advances FR-1, FR-2, FR-3)
