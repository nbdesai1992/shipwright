# Eval System Design: Software Factory

> **Status (2026-09-16): design document, predates the brief-board architecture.** Written when workers were spawned with `claude -p --agent` and state lived in `session/spec.md`, `session/phases/`, and `session/tasks/`. Since decisions #20–#24 the factory uses native subagents (Task tool), a committed `briefs/` Kanban board, and hook-written `session/{brief-id}/trajectory.jsonl`. The eval tasks, scoring rubrics, and best@k framing still apply; the spawn mechanics, file paths, and "Factory Changes Required" sections do not. Treat `trajectory.jsonl` (hook-written, deterministic) as the ground-truth trace the harness should read.

## The Core Thesis

The software factory produces working software from specs. Today we can't answer: "How good is the software it produces?" or "Did it follow its own process?" We have trajectory logging and compliance self-audits, but no systematic way to measure, compare, or improve.

An eval system gives us three things:
1. **Measurement** — Quantified quality across runs, tasks, and factory versions
2. **Diagnosis** — When something fails, trace it to the exact skill/step that broke
3. **Improvement signal** — Change a skill, re-run evals, see if the score goes up

With best@k, we also distinguish between **capability** (what the factory *can* do on its best run) and **reliability** (what it *consistently* does).

---

## The 5 Eval Tasks

These are ordered by complexity and chosen to exercise distinct failure surfaces. Together they cover every worker type, every skill, and the most common failure modes.

### Task 1: "Todo API" (Backend-Only Baseline)

**Spec:** Build a REST API for managing todos. CRUD endpoints (create, list, get, update, delete). Todos have title, description, completed status, created_at. PostgreSQL storage. Input validation.

**Config:** `backend_framework: fastapi, database: postgresql, frontend_framework: none, deploy_platform: none`

**Why this task:** Isolates the backend pipeline with zero confounders. No frontend, no infra, no cross-worker coordination. If the factory can't get this right, nothing else matters.

**What it exercises:**
- Spec → requirement decomposition (should be 1 phase, 1-2 tasks)
- backend-test skill (TDD, real DB, test categories)
- worker-protocol (task lifecycle, interface contracts, trajectory logging)
- Orchestrator basics (spawn, monitor, complete)

**Failure modes targeted:**
- Worker mocks the database instead of using real PostgreSQL
- Tests only cover happy path (no validation, no edge cases)
- Worker doesn't document interface contract for API shape
- Task file left in `in-progress` (worker forgets to set `completed`)
- Trajectory logging skipped or sparse

#### Rubric

**Process (40 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| SKILLS_LOADED event present with correct skills listed | 5 | Parse trajectory.md for event |
| Task file lifecycle correct (pending → in-progress → completed) | 5 | Read task file frontmatter |
| Interface contract documents all 5 CRUD endpoints with shapes | 5 | Parse task file `## Interface Contract` |
| Trajectory has START_TASK, ≥3 action events, COMPLETE_TASK | 5 | Parse trajectory.md event sequence |
| SKILL_COMPLIANCE event present with all items marked | 5 | Parse trajectory.md for event |
| "Did NOT mock the database" marked ✓ in compliance | 5 | Parse compliance event |
| Turn-log checkpoint written with cost + session_id | 5 | Parse session/turn-log.json |
| Decomposition appropriate (not over-engineered for simple task) | 5 | Count phases and tasks; 1 phase / 1-2 tasks expected |

**Output (40 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| All 5 CRUD endpoints exist and are importable | 10 | Static analysis or import check |
| Tests exist covering happy path | 5 | Parse test file for ≥1 create + ≥1 read test |
| Tests exist covering validation (e.g., missing title → 422) | 5 | Parse test file for validation assertions |
| Tests exist covering edge cases (empty list, not-found → 404) | 5 | Parse test file for edge case assertions |
| All tests pass when run (`pytest -v`) | 10 | Execute tests, check exit code |
| Schema matches spec (title, description, completed, created_at) | 5 | Parse model/migration file |

**Trace Quality (20 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Every trajectory event has ISO timestamp | 5 | Regex parse all `### Step` lines |
| Reasoning field populated (not empty/generic) in ≥50% of events | 5 | Parse reasoning fields, check non-empty |
| Files field in trajectory events matches actual git diff | 5 | Compare trajectory file lists vs `git diff --name-only` |
| Compliance ✓/✗ items match observable reality (e.g., "wrote tests" → test files exist) | 5 | Cross-reference compliance claims against filesystem |

**Total: 100 points**

---

### Task 2: "Coffee Roastery Landing Page" (Frontend-Only, Design)

**Spec:** Build a landing page for "Ember & Oak Roasters," an artisan coffee roastery. Hero section with tagline, featured roasts section (3 coffees with origin, tasting notes, altitude), about section with roastery story, newsletter signup form. Mobile responsive. The design should feel like stepping into a warm, wood-paneled roastery — not a tech startup.

**Config:** `frontend_framework: nextjs, backend_framework: none, database: none, deploy_platform: none, domain: "artisan coffee roastery"`

**Why this task:** Isolates the frontend pipeline and bold-design skill. Design quality is the hardest thing to evaluate — this task forces us to build rubrics for subjective quality.

**What it exercises:**
- bold-design pre-design exploration (domain vocabulary, color world, signature element, rejected defaults)
- bold-design rules (typography, color, layout, atmosphere, components)
- bold-design quality gates (AI Slop, Swap, Squint, Signature)
- verify-ui screenshot loop
- worker-protocol in frontend context

**Failure modes targeted:**
- Worker skips pre-design exploration entirely
- Design uses Inter/Roboto/system fonts despite prohibition
- Purple-to-blue gradient or generic SaaS palette
- Symmetric 3-card grid for featured roasts (explicit layout anti-pattern)
- No screenshots taken (verify-ui skipped)
- Quality gates self-reported as ✓ but design clearly fails them
- No session/design-direction.md created

#### Rubric

**Process (35 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| SKILLS_LOADED event lists worker-protocol, bold-design, verify-ui | 5 | Parse trajectory.md |
| Pre-design exploration present in trajectory with all 4 sections | 5 | Parse trajectory for domain vocabulary, color world, signature element, rejected defaults |
| session/design-direction.md created | 3 | Check file exists |
| ≥1 screenshot taken via dev-browser (file exists) | 5 | Check screenshot paths in trajectory exist on disk |
| Quality gates explicitly evaluated in trajectory (all 4 named) | 5 | Parse trajectory for "AI Slop", "Swap", "Squint", "Signature" |
| SKILL_COMPLIANCE event with bold-design items marked | 5 | Parse trajectory.md |
| Dev server started and killed properly | 2 | Trajectory shows startup; no orphan process |
| ≥2 screenshot iterations (evidence of iteration, not one-shot) | 5 | Count screenshot events in trajectory |

**Output — Mechanical (25 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Page renders without errors (dev server starts, curl returns 200) | 5 | Start server, curl health check |
| No prohibited fonts in CSS (Inter, Roboto, Arial, Open Sans, system-ui) | 5 | Grep CSS/styled files for prohibited font names |
| Colors defined as CSS custom properties on :root | 3 | Parse CSS for `:root` with `--` custom properties |
| Hero section, featured roasts, about section, newsletter form all present | 5 | Parse HTML output for expected sections |
| Mobile responsive (has media queries or responsive units) | 3 | Grep for `@media` or responsive CSS patterns |
| WCAG AA contrast on primary text (4.5:1 ratio) | 4 | Extract color values, compute contrast ratio |

**Output — LLM-as-Judge Design Quality (25 points)**

Provide the judge: screenshots, design-direction.md, the spec, and the bold-design skill rules. Judge scores:

| Item | Points | Judge Prompt |
|------|--------|-------------|
| Domain authenticity: Does it feel like a coffee roastery, not a tech startup? | 7 | "Looking at these screenshots, does the design evoke an artisan coffee roastery? Would you mistake it for a generic SaaS product?" |
| Typography distinctiveness: Are type choices specific and intentional? | 5 | "Evaluate the typography. Are the font choices distinctive and domain-appropriate? Do headings use dramatic weight/size contrasts (not 400 vs 600)?" |
| Signature element visible: Can you point to something unique to THIS product? | 5 | "Is there a visual signature element — something unique that could only exist for this coffee roastery? Describe it." |
| Layout intentionality: Non-generic structure? | 4 | "Is the layout structurally interesting (asymmetry, overlap, grid-breaking elements)? Or is it a predictable symmetric card grid?" |
| Overall impression: Would someone say "AI made this"? | 4 | "If you showed this to a designer and said 'AI made this,' would they immediately believe you? Score 0 if yes, 4 if no." |

**Trace Quality (15 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Pre-design exploration reasoning is domain-specific (mentions coffee, roasting, wood, warmth — not generic) | 5 | LLM-as-judge on exploration text |
| Screenshot analysis in trajectory references specific visual elements (not generic "looks good") | 5 | LLM-as-judge on trajectory analysis entries |
| Compliance self-report matches observable design decisions | 5 | Cross-reference "✓ Applied domain-specific typography" against actual font choices |

**Total: 100 points**

---

### Task 3: "Bookmark Manager" (Full-Stack Minimal)

**Spec:** Build a bookmark manager. Users can save URLs with title and tags, view bookmarks as a list, filter by tag, delete bookmarks. Backend API stores bookmarks in PostgreSQL. Frontend shows bookmark list with tag filter. No auth required.

**Config:** `frontend_framework: nextjs, backend_framework: fastapi, database: postgresql, deploy_platform: none, domain: "personal productivity"`

**Why this task:** The simplest possible full-stack task. Tests cross-worker coordination (backend produces interface contract → frontend consumes it) without the complexity of auth or deploy.

**What it exercises:**
- Orchestrator decomposition for full-stack work (should be 2 phases: backend → frontend)
- Interface contract handoff (backend documents API → frontend reads it)
- Both worker types executing correctly
- Both test skills (backend-test TDD + verify-ui screenshots)
- bold-design in a non-heroic context (functional UI, not landing page)

**Failure modes targeted:**
- Frontend worker ignores backend's interface contract (invents its own API shape)
- Task dependency ordering wrong (frontend spawned before backend)
- File ownership conflict (both workers modify same config file)
- Frontend calls wrong API endpoints (contract mismatch)
- No tag filtering implemented (common requirement drop)

#### Rubric

**Process (35 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Decomposition: ≥2 phases, backend before frontend | 5 | Read phase files, verify ordering |
| Backend task has interface contract with endpoint shapes | 5 | Parse completed backend task file |
| Frontend task lists backend task as dependency | 5 | Parse frontend task file `depends_on` field |
| Frontend worker reads backend interface contract (trajectory evidence) | 5 | Parse trajectory for READ_FILE event targeting completed backend task |
| No file ownership conflicts within any phase | 5 | Compare `files_owned` across tasks in same phase — no overlap |
| Both workers log SKILLS_LOADED and SKILL_COMPLIANCE | 5 | Parse trajectory for both events from both worker types |
| Phase transitions logged in trajectory | 5 | Parse for PHASE_TRANSITION events |

**Output (45 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Backend: All CRUD endpoints work (create, list, delete bookmark) | 8 | Run backend tests or curl endpoints |
| Backend: Tag filtering endpoint works | 4 | Test with `?tag=X` parameter |
| Backend: Tests pass | 5 | Execute `pytest -v` |
| Frontend: Bookmark list renders | 5 | Screenshot or parse HTML output |
| Frontend: Tag filter UI exists and is functional | 5 | Screenshot with filter interaction |
| Frontend: Delete works (button exists, calls correct endpoint) | 4 | Parse frontend code for delete handler + correct API path |
| Integration: Frontend API calls match backend interface contract | 8 | Compare frontend fetch URLs/shapes against backend contract |
| Frontend: No prohibited fonts, has custom properties | 3 | Grep CSS for prohibited fonts |
| All spec requirements covered (5 requirements, 1 point each) | 3 | Map each FR to implementation evidence |

**Trace Quality (20 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Trajectory captures cross-worker dependency chain | 5 | Verify backend COMPLETE_TASK appears before frontend START_TASK |
| Interface contract in trajectory matches actual API shape | 5 | Compare documented contract vs actual endpoint signatures |
| Decision log captures any non-obvious choices (e.g., tag storage: array vs junction table) | 5 | Parse decisions.md for at least 1 architectural decision |
| Cost tracked per worker in turn-log | 5 | Parse turn-log for worker_sessions with cost_usd |

**Total: 100 points**

---

### Task 4: "Recipe Sharing App with Auth + Deploy" (Full Pipeline)

**Spec:** Build a recipe sharing app. Users sign up via Clerk, create recipes (title, ingredients list, steps, prep time, cuisine type), browse all recipes, filter by cuisine. Only recipe owner can edit/delete. Deploy to Render. PostgreSQL database.

**Config:** `frontend_framework: nextjs, backend_framework: fastapi, database: postgresql, deploy_platform: render, auth_provider: clerk, domain: "home cooking community"`

**Why this task:** The full pipeline — infrastructure, auth, backend, frontend, deploy, verification. This is the "acceptance test" for the factory. If it can do this reliably, it can build real products.

**What it exercises:**
- Infrastructure-first phasing (Phase 1: infra audit + DB setup)
- Auth as infrastructure (Clerk middleware before user endpoints)
- Multi-phase decomposition (infra → backend + deploy → frontend + deploy → verify)
- Deploy skill (workspace verification, state audit, cross-service URLs)
- Post-push deploy verification (commit SHA matching)
- All three worker types
- Resume protocol (likely spans multiple orchestrator turns)

**Failure modes targeted:**
- Infra worker skips state audit (marks ✓ without actually checking Render)
- Auth middleware not applied to protected endpoints
- Owner-only edit/delete not enforced (auth scoping failure)
- Frontend calls localhost instead of deployed API URL
- Deploy verification checks health but not commit SHA (stale deploy)
- Cross-service env vars not set (CORS failures in production)
- Worker creates Render services via API instead of blueprint

**Important note:** This task requires real Render infrastructure. For eval purposes, either:
- (a) Use a dedicated eval Render workspace with pre-created blueprint instances
- (b) Mock the deploy layer (loses deploy-skill coverage but tests everything else)
- (c) Run the non-deploy variant and test deploy separately

#### Rubric

**Process (35 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Infrastructure-first: Phase 1 is infra (not backend) | 3 | Read phase-1 file, verify type is infra |
| Infra worker performs state audit (trajectory evidence) | 5 | Parse trajectory for Render API calls: env vars, services, env groups |
| Auth task exists and completes before user-facing endpoints | 3 | Verify auth task in dependency chain for CRUD tasks |
| ≥3 phases decomposed (infra, backend, frontend minimum) | 3 | Count phase files |
| Deploy tasks present for both backend and frontend | 3 | Search task files for deploy-related tasks |
| Cross-service env vars set (API_URL, FRONTEND_URL, CORS_ORIGINS) | 5 | Parse infra task trajectory for env var API calls |
| No services created via API (compliance with "blueprint-only" rule) | 3 | Grep trajectory for `POST /v1/services` — should be absent |
| Post-push deploy verification checks commit SHA (not just health) | 5 | Parse trajectory for deploy commit SHA check |
| All three worker types spawn with correct SKILLS_LOADED | 5 | Parse trajectory for 3 distinct SKILLS_LOADED events |

**Output (45 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Backend: Auth middleware protects recipe CRUD endpoints | 5 | Read middleware code, verify route protection |
| Backend: Unauthenticated requests return 401 | 3 | Test endpoint without auth header |
| Backend: Owner-only edit/delete enforced (other users get 403) | 5 | Read endpoint code for user_id check |
| Backend: All CRUD endpoints functional | 5 | Run backend tests |
| Backend: Tests pass against real DB | 5 | Execute tests, verify DATABASE_URL is remote |
| Backend: Cuisine filter works | 3 | Test with `?cuisine=X` parameter |
| Frontend: Signup/login flow renders | 3 | Screenshot or parse for Clerk components |
| Frontend: Recipe list + filter UI functional | 4 | Screenshot showing recipe cards + filter |
| Frontend: Edit/delete only visible for owned recipes | 4 | Logic check in frontend code |
| Frontend: Calls deployed backend URL (not localhost) | 3 | Grep frontend for API_URL usage, verify not hardcoded localhost |
| Deployed: Backend health check returns 200 | 3 | curl deployed health endpoint |
| Deployed: Frontend loads (200 response) | 2 | curl deployed frontend URL |

**Trace Quality (20 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Full trajectory from infra → backend → frontend → deploy → verify | 5 | Verify event sequence covers all phases |
| Blocker protocol used correctly (if blockers arise) | 3 | If blockers exist, verify format and resolution |
| Turn-log captures multi-turn progression (if applicable) | 4 | Verify turn-log has multiple entries with resume_hints |
| SKILL_COMPLIANCE from all 3 worker types present | 3 | Count distinct worker-type compliance events |
| Deploy verification trajectory distinguishes health check from commit SHA check | 5 | Parse deploy verification events for both checks |

**Total: 100 points**

---

### Task 5: "Add Search to Existing Book Catalog" (Incremental Feature)

**Spec:** An existing book catalog app has: book listing, book detail view, add book form. Add full-text search: search bar on listing page, backend search endpoint that searches title + author, highlight matching terms in results, search-as-you-type with debounce.

**Config:** Same as whatever the existing app uses. The key difference: the factory starts with a non-empty codebase.

**Pre-condition:** A pre-built "book catalog" app exists in the eval repo (we provide this). It has:
- Backend: Book model, CRUD endpoints, tests
- Frontend: List page, detail page, add form
- Working tests, passing CI

**Why this task:** The factory isn't always starting from scratch. Real usage often means adding features to existing code. This tests whether the factory can understand existing patterns, decompose incrementally, and not break what already works.

**What it exercises:**
- Spec analysis against existing codebase (not greenfield)
- Decomposition that respects existing architecture (don't restructure what works)
- Backend worker extending existing models/endpoints (not creating from scratch)
- Frontend worker modifying existing pages (not building new ones)
- Test preservation (existing tests must still pass after changes)
- Interface contract for search endpoint that integrates with existing API patterns

**Failure modes targeted:**
- Worker rewrites existing files from scratch instead of extending them
- Existing tests broken by changes (regression)
- Search endpoint doesn't follow existing API patterns (e.g., different URL scheme)
- Frontend creates separate search page instead of adding to existing listing
- Debounce not implemented (search fires on every keystroke)
- Over-decomposition (10 tasks for what should be 2-3)
- Worker ignores existing code patterns (different naming convention, different file structure)

#### Rubric

**Process (30 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Decomposition: 1-2 phases, ≤4 tasks (appropriate for incremental work) | 5 | Count phases/tasks — penalize over-engineering |
| Worker reads existing code before writing (READ_FILE events for existing files in trajectory) | 5 | Parse trajectory for READ_FILE events targeting existing backend/frontend files |
| Existing file ownership respected (worker extends, doesn't rewrite from scratch) | 5 | Git diff shows modifications, not wholesale file replacements |
| New search endpoint follows existing URL pattern (e.g., if existing is `/api/books`, search is `/api/books/search` or `/api/books?q=`) | 5 | Compare new endpoint pattern against existing ones |
| Interface contract for search endpoint documented | 5 | Parse completed backend task file |
| backend-test compliance: new tests + existing tests pass | 5 | Parse SKILL_COMPLIANCE for test items |

**Output (50 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Search endpoint exists and returns filtered results | 8 | Curl endpoint with query parameter |
| Search covers both title AND author | 5 | Test with title-only match and author-only match |
| New tests for search endpoint (happy path, empty query, no results) | 5 | Parse test file for search-specific tests |
| ALL existing tests still pass (zero regressions) | 10 | Run full test suite, compare against pre-change baseline |
| Frontend: Search bar added to existing listing page (not separate page) | 5 | Diff shows modification of existing page component |
| Frontend: Search-as-you-type with debounce implemented | 5 | Grep for debounce logic (setTimeout/debounce import) |
| Frontend: Matching terms highlighted in results | 4 | Grep for highlight/mark logic in search results component |
| Frontend: No existing UI broken (other pages still render) | 5 | Screenshot non-search pages, verify they still work |
| Code follows existing patterns (naming, file structure, import style) | 3 | LLM-as-judge comparison of new code vs existing style |

**Trace Quality (20 points)**

| Item | Points | Verification Method |
|------|--------|-------------------|
| Trajectory shows awareness of existing codebase (references existing files, patterns) | 5 | LLM-as-judge on trajectory reasoning fields |
| Decision log explains integration choices (why this URL pattern, why this search approach) | 5 | Parse decisions.md for search-related decisions |
| Compliance accurately reflects incremental nature (not claiming to have "created" things that existed) | 5 | Cross-reference compliance claims against git diff |
| Trajectory doesn't show unnecessary file rewrites | 5 | Parse WRITE_FILE events — flag if existing files fully rewritten |

**Total: 100 points**

---

## best@k Methodology

### What It Means

For each eval task, run the factory **k times** independently (fresh session directory each time, same spec). This produces k scored runs. We report:

| Metric | Definition | What It Tells You |
|--------|-----------|------------------|
| **best@k** | Max score across k runs | Capability ceiling — what the factory *can* do |
| **median@k** | Median score across k runs | Typical performance — what you'll usually get |
| **pass@k** | % of runs scoring above threshold (e.g., 70/100) | Reliability — how often it "works" |
| **worst@k** | Min score across k runs | Failure floor — how bad it can get |
| **spread** | best@k − worst@k | Consistency — larger spread = more variance |

### Recommended k Values

- **Initial development:** k=3 (fast iteration, enough to spot obvious issues)
- **Pre-ship validation:** k=5 (statistically meaningful, catches intermittent failures)
- **Deep investigation of specific failure:** k=10 (reveals distribution shape)

### Interpreting Results

| Pattern | Diagnosis | Action |
|---------|-----------|--------|
| High best@k, low median@k | Factory can do it but unreliably | Tighten skill instructions, add more constraints |
| Low best@k | Factory fundamentally can't do this | Skill gap — need new capability or restructured approach |
| High median@k, low worst@k | Occasional catastrophic failure | Find the trigger — usually one specific failure mode |
| Tight spread, moderate scores | Consistently mediocre | Systemic issue — skill instructions may be unclear or conflicting |
| Tight spread, high scores | Reliable success | Working as intended |

### Cost Tracking

Each run records `cost_usd` per worker in `turn-log.json`. Aggregate:
- **cost@k**: Total cost across all k runs
- **cost_per_run**: Average cost per run
- **cost_per_point**: cost_per_run / median_score (efficiency metric)

This matters because a skill change that improves score by 5 points but doubles cost may not be worth it.

---

## The Harness

Yes, a harness is needed. Without it, you're manually running specs and eyeballing trajectories. The harness automates: setup → run → capture → judge → report.

### Architecture

```
eval-harness/
├── tasks/                    # Eval task definitions
│   ├── 01-todo-api/
│   │   ├── spec.md           # Pre-written spec (skip interview)
│   │   ├── config.json       # Onboarding config for this task
│   │   ├── rubric.yaml       # Machine-parseable rubric
│   │   ├── judge-prompts/    # LLM-as-judge prompt templates
│   │   └── seed/             # Pre-existing codebase (if incremental task)
│   ├── 02-coffee-landing/
│   ├── 03-bookmark-manager/
│   ├── 04-recipe-app/
│   └── 05-add-search/
│       └── seed/             # The existing book catalog app
├── harness.py                # Main orchestrator
├── judge.py                  # LLM-as-judge scoring
├── parsers/                  # Trajectory and artifact parsers
│   ├── trajectory.py         # Parse trajectory.md into structured events
│   ├── task_files.py         # Parse task file frontmatter + sections
│   ├── compliance.py         # Parse SKILL_COMPLIANCE events
│   ├── turn_log.py           # Parse turn-log.json
│   └── code_quality.py       # Static analysis helpers
├── validators/               # Mechanical rubric validators
│   ├── process.py            # Check event sequences, file existence
│   ├── output.py             # Run tests, check endpoints, verify files
│   └── trace.py              # Cross-reference compliance vs reality
├── results/                  # Stored run results
│   └── {task}/{run-id}/
│       ├── session/          # Complete session directory snapshot
│       ├── code-diff.patch   # Git diff of all changes
│       ├── scores.json       # Per-rubric-item scores
│       └── judge-output/     # LLM-as-judge reasoning
└── reports/                  # Aggregate reports
    ├── latest.md             # Most recent full eval run
    └── history.json          # Score trends over time
```

### Execution Flow

```
harness.py run --task 01-todo-api --k 3

For each of k runs:
  1. SETUP
     - Create temp directory (or git worktree)
     - Run onboard.py with config.json (programmatic, non-interactive)
     - Copy spec.md → session/spec.md (skip /spec create interview)
     - Copy seed/ if it exists (for incremental tasks)
     - Git init + initial commit (clean baseline for diff)

  2. EXECUTE
     - Run: claude -p "/orchestrate" \
              --permission-mode bypassPermissions \
              --output-format json \
              --max-budget-usd 100 \
              > run-output.json 2>&1
     - Capture exit code, cost, duration
     - If orchestrator surfaces blocker requiring human input:
       → For eval, pre-configure responses in config.json
       → Or: mark run as "blocked" and score accordingly

  3. CAPTURE
     - Snapshot entire session/ directory
     - Generate git diff (all changes since initial commit)
     - Copy any screenshots to results
     - Record total cost (sum of worker costs from turn-log)

  4. JUDGE — MECHANICAL
     - Parse trajectory.md → structured events
     - Parse task files → status, contracts, compliance
     - Run rubric validators (file existence, test execution, grep checks)
     - Score each mechanical rubric item (0 or full points, no partial)

  5. JUDGE — LLM
     - For design quality items: send screenshots + rubric prompt to judge model
     - For trace quality items: send trajectory + rubric prompt to judge model
     - For code quality items: send code + existing code + rubric prompt to judge model
     - Score each LLM-judged item (0 to max points, with reasoning)

  6. SCORE
     - Aggregate per-item scores into total
     - Write scores.json with per-item breakdown
     - Write judge reasoning to judge-output/

After k runs:
  7. REPORT
     - Compute best@k, median@k, pass@k, worst@k, spread
     - Per-rubric-item variance (which items are flaky?)
     - Total cost across k runs
     - Write report to reports/
```

### Handling Blockers in Eval

The factory's blocker protocol expects a human in the loop. For evals, three options:

1. **Pre-scripted responses:** `config.json` includes a `blocker_responses` map. When the harness detects a blocker, it writes the pre-scripted response to `session/blockers.md` and resumes the orchestrator. This tests the blocker→resolution→re-spawn flow.

2. **Blocker = failure:** If a blocker is surfaced that isn't pre-scripted, the run gets scored as-is (partial completion). This is valid — we're measuring how far the factory gets autonomously.

3. **Infrastructure pre-provisioning:** For Task 4 (deploy), pre-create the Render blueprint instance, set secrets, and provide actual URLs in config. The infra worker's job becomes verification, not creation.

### Making `onboard.py` Scriptable

`onboard.py` currently uses interactive prompts. For the harness, we need a non-interactive mode:

```bash
python onboard.py --config tasks/01-todo-api/config.json --target /tmp/eval-run-001
```

This reads all answers from `config.json` instead of prompting. The config already stores in `factory-config.json`, so this is a natural extension — just read the config upfront instead of collecting it interactively.

---

## Ensuring Trace Accuracy and Completeness

This is the hardest problem. The trajectory is currently self-reported — workers write their own logs. A worker that skips trajectory logging is invisible. A worker that lies in its compliance audit is trusted.

### Layer 1: Structural Validation (Mechanical, Zero Trust)

These checks verify that the trace EXISTS and has the right SHAPE, regardless of content accuracy.

**Event sequence validation:**
```
For each worker invocation:
  ASSERT: SKILLS_LOADED event exists (first event from this worker)
  ASSERT: START_TASK event exists
  ASSERT: ≥1 action event between START_TASK and COMPLETE_TASK
  ASSERT: SKILL_COMPLIANCE event exists (before COMPLETE_TASK)
  ASSERT: COMPLETE_TASK event exists (last event from this worker)
  ASSERT: All events have ISO timestamps
  ASSERT: Timestamps are monotonically increasing
  ASSERT: Task ID in events matches assigned task ID
```

**Missing events are scored as 0 for the corresponding rubric items.** This incentivizes the factory to log everything, because missing logs = lost points.

### Layer 2: Cross-Reference Validation (Mechanical, Verify Claims)

These checks verify that what the trace SAYS happened actually DID happen.

**Compliance cross-reference:**
```
For each ✓ item in SKILL_COMPLIANCE:
  "Wrote tests" → ASSERT: test files exist in git diff
  "Ran tests against real database" → ASSERT: DATABASE_URL in .env is not sqlite://
  "Took screenshots via dev-browser" → ASSERT: screenshot files exist on disk
  "Did NOT mock the database" → ASSERT: no mock/patch/MagicMock in test files
  "Updated render.yaml for env vars" → ASSERT: render.yaml in git diff (if applicable)
  "Read task file and checked dependencies" → ASSERT: READ_FILE event for task file in trajectory
```

**File modification cross-reference:**
```
For each WRITE_FILE event in trajectory:
  ASSERT: file appears in git diff
  ASSERT: file is in task's files_owned list

For each file in git diff:
  ASSERT: corresponding WRITE_FILE event in trajectory
  (Missing event = incomplete logging)
```

**Interface contract cross-reference:**
```
Parse interface contract from completed task file
Parse actual endpoint signatures from code
ASSERT: contract endpoints match code endpoints (paths, methods, shapes)
```

### Layer 3: LLM-as-Judge Validation (Semantic, Verify Quality)

These checks verify that the trace content is MEANINGFUL, not boilerplate.

**Reasoning quality:**
```
Prompt: "Below are the reasoning fields from an agentic trajectory. Rate each on
a 1-5 scale for specificity. A '1' is generic ('implemented the feature'), a '5'
is specific ('chose FastAPI's Depends() for auth injection because the existing
codebase uses dependency injection for database sessions, maintaining consistency').
Score 0 if the field is empty."
```

**Compliance honesty:**
```
Prompt: "Below is a SKILL_COMPLIANCE self-audit from a worker, alongside the actual
code produced (git diff) and the skill instructions it was supposed to follow. For
each ✓ item, rate whether the claim is honest (the worker actually did this) or
inflated (the worker claims compliance but the evidence doesn't support it). Flag
any ✗ items that should have been ✓ (worker was too conservative)."
```

### Layer 4: Trace-as-Test-Fixture

The most powerful use of traces: treat a "gold" trajectory from a best@k run as a reference. Future runs can be compared against it:

```
Given: gold trajectory (from best-scoring run)
Given: current trajectory (from new run)

Diff:
  - Were the same phases/tasks created? (decomposition stability)
  - Did workers follow similar event sequences? (process stability)
  - Did quality gates pass/fail on similar items? (design stability)
  - Was cost within 2x of gold run? (efficiency stability)
```

This lets you detect skill regression: if a factory change causes trajectories to diverge from known-good patterns, that's a signal.

---

## The Self-Improvement Loop

### V1: Human-in-the-Loop Improvement (Build This First)

```
1. Run eval suite (5 tasks × k=3 = 15 runs)
2. Generate report with per-item scores and failure analysis
3. Human reads report, identifies lowest-scoring rubric items
4. Human traces failure to specific skill file:
   - "Workers consistently score 0 on 'interface contract documents all endpoints'"
   - → Problem is in worker-protocol/SKILL.md, interface contract section
   - Or: orchestrator doesn't validate contracts before phase transition
5. Human (with Claude Code) edits the skill
6. Re-run eval suite
7. Compare: Did the target rubric items improve? Did anything regress?
8. If improved and no regression: commit the skill change
```

This is already enormously valuable. Most teams building agent systems have no systematic feedback loop. Even a manual one puts you ahead.

### V2: Semi-Automated Improvement

```
1. Run eval suite → report
2. Automated analysis:
   - Identify rubric items scoring < 60% pass@k
   - For each, trace to skill file via rubric metadata:
     rubric item "interface contract documents all endpoints"
       → skill: worker-protocol
       → section: Interface Contracts
       → file: factory/skills/worker-protocol/SKILL.md
3. Generate improvement spec:
   "The worker-protocol skill's Interface Contract section is not being
    followed reliably. In 7/15 runs, workers did not document all API
    endpoints in the contract. The current instruction says: '{quote}'.
    Proposed change: {LLM-generated suggestion based on failure analysis}"
4. Human reviews proposed change, approves or edits
5. Apply change, re-run evals
```

The key insight: the rubric items themselves point to which skill to fix. If you tag each rubric item with `skill_file` and `skill_section`, the diagnosis is automatic.

### V3: Factory-on-Factory (Aspirational)

```
1. Run eval suite → report → automated diagnosis → improvement spec
2. Onboard software-factory into itself:
   - The "project" is the factory repo
   - The "backend" is the Python onboard.py
   - The "frontend" is... nothing (it's markdown files)
   - The "workers" would need to understand they're editing skill definitions
3. /spec create "Improve worker-protocol interface contract compliance"
4. /orchestrate
5. Workers edit factory/skills/worker-protocol/SKILL.md
6. Re-run evals on the modified factory
7. If improved: commit
```

**Why this is hard:** The factory's worker types (backend, frontend, infra) don't map to "edit a markdown skill file." You'd need:
- A new worker type: `skill-writer` that understands skill structure, the eval rubric, and how to make targeted edits
- Or: skip the factory and use plain Claude Code (which is V2 above)

**When it becomes worth it:** When you have enough eval data to automatically generate high-quality improvement specs. The bottleneck isn't making the edits — Claude Code can do that. The bottleneck is knowing *what* to change, which requires the eval system to produce actionable diagnosis.

### The Refresh Cycle

After any factory change, the eval baseline must be refreshed:

```
1. Run full eval suite on new factory version
2. Store results as new baseline in results/
3. Compare against previous baseline:
   - Per-task score deltas
   - Per-rubric-item score deltas
   - Cost deltas
   - New failure modes introduced?
4. If regression detected:
   - Flag which tasks regressed
   - Flag which rubric items regressed
   - This becomes the next improvement target
```

Over time, `history.json` shows score trends per task, per rubric item, per factory version. You can plot improvement curves and identify which skill changes had the most impact.

---

## Practical Sequencing: What to Build When

### Phase 1: Foundation (get signal flowing)

**Build:**
1. Task 1 spec + config + rubric (Todo API — simplest possible)
2. Trajectory parser (parse trajectory.md → structured events)
3. Mechanical validators (event sequence, file existence, test execution)
4. Non-interactive onboard.py mode (`--config flag`)
5. Minimal harness: setup → run → capture → mechanical score → report

**Skip for now:** LLM-as-judge, design tasks, deploy tasks, best@k aggregation

**Goal:** Can you run Task 1 once and get a score? Does the score reflect reality?

### Phase 2: Coverage (exercise more failure surfaces)

**Build:**
1. Tasks 2-3 specs + configs + rubrics
2. LLM-as-judge for design quality (Task 2)
3. Cross-reference validators (compliance vs reality)
4. best@k runner (run k times, aggregate)
5. Results storage and comparison

**Goal:** Three tasks with k=3. Can you identify which rubric items are flaky?

### Phase 3: Full Suite (comprehensive evaluation)

**Build:**
1. Tasks 4-5 specs + configs + rubrics
2. Pre-built seed codebase for Task 5
3. Blocker pre-scripting for Task 4
4. Render eval workspace (or deploy mocking)
5. History tracking across factory versions

**Goal:** Five tasks with k=3-5. Full report with trends.

### Phase 4: Improvement Loop (close the feedback cycle)

**Build:**
1. Rubric-to-skill mapping (each rubric item tagged with source skill file)
2. Automated diagnosis (low-scoring items → skill change suggestions)
3. Before/after comparison tooling
4. Regression detection

**Goal:** Change a skill, re-run evals, see the score change. The flywheel turns.

---

## Open Questions

1. **Judge model selection.** Should the LLM-as-judge be the same model as the factory workers, or a different one? Same model may share blind spots. Different model adds cost and potential disagreement. Recommendation: use the same model family but at a higher capability tier if available, or use a panel of 2 models and take the stricter score.

2. **Eval contamination.** If the factory learns from eval specs (via memory or CLAUDE.md), it may overfit. Keep eval specs OUT of the factory's context — they live in the harness, not the project.

3. **Cost budget per eval run.** At $50 max per worker, a full-stack task with 6+ workers could cost $300 per run. At k=5 that's $1,500 per task, $7,500 for the full suite. This needs to be tracked and budgeted. The cost_per_point metric helps justify the spend.

4. **Non-determinism sources.** LLM temperature is one source, but also: network latency to Render, database state, dev server startup timing. The harness should log all environmental variables that could affect reproducibility.

5. **Eval task maintenance.** As the factory evolves (new worker types, new skills), eval tasks need updating. The eval suite itself needs a maintenance plan — treat it like a test suite, not a one-time thing.

6. **Threshold calibration.** What score counts as "pass"? This needs to be set empirically after the first few runs, not theoretically. Run the suite, look at the distribution, set the threshold where it meaningfully separates "worked" from "didn't work."
