# Decomposition Patterns

Phase-aware examples for different types of development goals.

## Phase Ordering Principle: Infrastructure First

When a deployment platform is configured (CLAUDE.md has a `deploy_platform`), **always provision infrastructure first**. This gives workers real databases and live API endpoints from the start — no mocks, no local stand-ins, no environment drift.

```
infra → backend (deploy after) → frontend (local dev, hits deployed API) → frontend deploy
```

The frontend dev server runs locally for fast visual iteration but proxies API calls to the deployed backend. This means every screenshot shows real data from a real API backed by a real database.

## Pattern: Full-Stack Feature

Goal: "Add user registration with API and UI"

### Phases
```
phase-1: Infrastructure Setup (NFR-1)
    p1-task-1: Infra foundation → infra-worker
               1. Verify workspace + credential (deploy skill pre-flight)
               2. Run `python3 .claude/scripts/provision.py --yes` — idempotent: creates
                  anything render.yaml declares that is missing, sets cross-service URLs,
                  writes backend/.env, writes .claude/render-services.json
               3. If it FAILs: relay its `→ fix` line as an external-action blocker
                  (no payment method / GitHub not connected to Render / expired credential)
               4. Audit env vars: compare live Render state against render.yaml, flag drift
               5. Verify DB connectivity from backend/.env
               6. Record actual URLs (from .claude/render-services.json) in the final
                  report's Interface Contracts

phase-2: Backend Development (FR-1, FR-2, FR-3)
    p2-task-1: Auth middleware setup (if auth configured in CLAUDE.md) → backend-worker
               Clerk: verify JWT tokens, create auth dependency for protected routes.
               This MUST come before any user-specific models or endpoints.
    p2-task-2: Database models + migrations (run against Render DB via .env) → backend-worker (depends on p2-task-1 if models need user_id)
    p2-task-3: API endpoints, tested against Render DB → backend-worker (depends on p2-task-2)
    p2-task-4: Commit code, then deploy per CLAUDE.md push policy:
               human → raise blocker for the human to push;
               consul → the RUNNER runs `git push` itself (workers never push).
               After push: poll deploy status until live or failed.
               If failed: pull build logs, raise blocker with error.
               If live: verify health endpoints. → infra-worker (depends on p2-task-3)

phase-3: Frontend Development (FR-1, FR-2, NFR-2)
    p3-task-1: Registration UI + dashboard (local dev, wired to deployed backend API) → frontend-worker
    p3-task-2: Polish + local visual verification → frontend-worker (depends on p3-task-1)
    p3-task-3: Commit code, then deploy per push policy (as p2-task-4).
               After push: poll deploy status until live or failed.
               If failed: pull build logs, raise blocker with error.
               If live: verify health endpoints. → infra-worker (depends on p3-task-2)
    p3-task-4: Post-deploy verification — screenshot deployed frontend URL,
               verify against requirements + design direction → frontend-worker (depends on p3-task-3)
```

Key points:
- Infrastructure first, via the provisioner. `provision.py` creates whatever render.yaml declares and writes backend/.env with DB credentials. Nobody creates Render resources by hand.
- Backend tests run against the REAL Render database (no mocks, no SQLite).
- Deploy tasks commit code, then follow the **push policy in CLAUDE.md**: `human` → raise a BLOCKER for the human to `git push` (review checkpoint); `consul` (legacy `shipwright`) → the runner pushes. Render auto-deploys on push either way.
- Frontend development uses local dev server for visual iteration, wired to deployed backend API.
- Post-deploy verification screenshots the LIVE deployed URL (not localhost).
- Each phase decomposes just-in-time.

## Pattern: Frontend Only

Goal: "Redesign the dashboard with a fresh visual identity"

### Phases
```
phase-1: UI Redesign (FR-1, NFR-1)
    p1-task-1: Design exploration + implementation → frontend-worker
    p1-task-2: Responsive testing                  → frontend-worker (depends on p1-task-1)
```

Single phase. Bold-design exploration happens within the frontend worker.

## Pattern: Backend Only

Goal: "Add authentication with JWT tokens"

### Phases
```
phase-1: Auth Foundation (FR-1, FR-2)
    p1-task-1: User model + migration        → backend-worker
    p1-task-2: JWT utility (sign, verify)     → backend-worker
    p1-task-3: Auth tests                     → backend-worker (depends on p1-task-1, p1-task-2)

phase-2: Auth Endpoints (FR-3, FR-4)
    (decomposed after phase-1)

phase-3: Auth Middleware (FR-5, NFR-1)
    (decomposed after phase-2)
```

Note: p1-task-1 and p1-task-2 have no dependency on each other, but in sequential mode they still run one at a time.

## Pattern: Infrastructure

Goal: "Add a PostgreSQL database and deploy the backend API"

### Phases
```
phase-1: Infrastructure (NFR-1, NFR-2)
    p1-task-1: Update render.yaml + run provision.py → infra-worker
    p1-task-2: Deploy and verify health endpoints    → infra-worker (depends on p1-task-1)
    p1-task-3: Run database migrations               → infra-worker (depends on p1-task-2)
```

## Pattern: Multi-Service

Goal: "Split into separate frontend and backend services"

### Phases
```
phase-1: Project Restructure (FR-1)
    p1-task-1: Create backend/ directory, move API code  → backend-worker
    p1-task-2: Create frontend/ directory, move UI code  → frontend-worker
    p1-task-3: Update imports and paths                  → backend-worker (depends on p1-task-1)

phase-2: Service Configuration (FR-2, NFR-1)
    (decomposed after phase-1 — needs to know final structure)

phase-3: Deployment (NFR-2)
    (decomposed after phase-2)
```

## Decomposition Rules

1. **File exclusivity within phase**: No two tasks share files. Merge if needed.
2. **Dependency minimization**: Keep chains shallow. Independent tasks have no `depends_on` (even though they execute sequentially, explicit dependencies document real data flow).
3. **Right-size tasks**: One worker, 5-30 minutes. Bigger → split. Smaller → merge.
4. **Test proximity**: Tests live with the code they test in the same task.
5. **Single concern**: One logical concern per task (one model, one endpoint set, one UI component).
6. **Setup tasks for shared files**: Use `p{n}-task-0-setup` for config files, env files, shared utilities that multiple tasks need.
