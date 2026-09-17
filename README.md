# Software Factory

**Prompt to production.** A Claude Code orchestration toolkit with pre-built skills, worker agents, and deployment configs that turns a product description into deployed, tested software — autonomously.

```
/spec create "build an invoice tracker for freelancers"
/goal <the prompt the spec skill hands you>
```

That's it. The factory handles decomposition, coding, testing, visual design, and deployment across backend, frontend, and infrastructure — with you in the loop only when it matters.

---

## How It Works

```
  You describe it           The factory builds it              You push to deploy

  "Build a..."   ──►  Brief ──► 2-active/ ──► 4-done/   ──►   Deployed on Render
                  (backlog)         │              or
                                    │          3-blocked/  ←  needs YOUR answer
                              /goal keeps it
                              running; workers
                              execute subtasks
```

1. **Onboard** — Run the setup wizard, pointed at a project directory (existing or not). Answer a few questions about your stack. The factory creates the repo, installs skills, agents, hooks, and the brief board, and pushes it to GitHub.
2. **Spec** — Describe what you want. The spec skill interviews you and produces a **goal brief**: a self-contained card on the `briefs/` Kanban board with requirements, acceptance criteria, and an embedded execution protocol — plus a ready-to-paste `/goal` prompt.
3. **Run** — Paste the `/goal` prompt. Claude Code keeps running turns until the brief reaches a terminal folder; each turn the runner delegates subtasks to specialized worker subagents, updates the brief, and proves board state. Human blockers are parked while everything else continues — the brief only lands in `3-blocked/` when nothing runnable remains.
4. **Deploy** — Infrastructure-first workflow. Backend deploys and tests against a real database before frontend work begins. You `git push` when ready — Render auto-deploys.

## What's In The Box

### Pre-Built Skills

| Skill | What It Does |
|-------|-------------|
| **orchestrate** | Board runner — selects the next brief, decomposes it into subtasks, delegates to worker subagents, verifies acceptance, routes to done or blocked |
| **spec** | Interactive requirements gathering — interviews you, produces goal briefs with acceptance criteria and their `/goal` prompts |
| **bold-design** | Fights generic AI aesthetics. Enforces domain-specific design: distinctive typography, color from the product's world, signature visual elements |
| **verify-ui** | Autonomous screenshot loop — takes screenshots via dev-browser, analyzes against requirements, iterates until the UI is right |
| **backend-test** | Test-driven backend development against real databases. No mocks, no SQLite substitutes |
| **deploy** | Full Render operations — CLI commands, API reference, blueprint schema, debugging playbooks |
| **worker-protocol** | Shared conventions for all worker subagents — read/write boundaries, blocker escalation, interface contracts, structured final reports |
| **status** | Board diagnostics — progress, blockers, requirement coverage, trajectory audit trail |
| **preflight** | Read-only readiness check — runs `.claude/scripts/preflight.py` and explains every failure with its fix |

### Worker Agents

| Agent | Skills | Purpose |
|-------|--------|---------|
| **backend-worker** | worker-protocol, backend-test | Models, migrations, API endpoints — tested against real cloud DB |
| **frontend-worker** | worker-protocol, bold-design, verify-ui | UI development with domain-specific design and visual verification |
| **infra-worker** | worker-protocol, deploy | Service provisioning, deployments, health verification |

### Generated Configs

Every onboarded project gets:

```
your-project/
├── CLAUDE.md               # Project context: stack, design direction, deployed URLs
├── render.yaml             # Render blueprint (monorepo: backend/ + frontend/)
├── briefs/                 # The brief board (committed): 1-backlog/ 2-active/
│                           #   3-blocked/ 4-done/ — folder location IS status
└── .claude/
    ├── settings.json       # Permissions + hooks wiring
    ├── hooks/              # brief-progress-guard (enforced docs), trajectory-log,
    │                       #   render-workspace-guard (fail-closed workspace pin)
    ├── scripts/            # render-api-key.sh (credential resolver), preflight.py
    ├── agents/             # 3 worker subagent definitions
    └── skills/             # 9 skills (orchestration + development + deployment + preflight)
```

## Usage

The full walkthrough, including the Render Dashboard steps, is in [SETUP.md](SETUP.md). The short version:

### Step 0: Install the tools (once per machine)

```bash
brew install render gh          # Render CLI + GitHub CLI
render login                    # opens a browser; stores a token in ~/.render/cli.yaml
gh auth login
npm install -g dev-browser      # headless browser the frontend worker uses for screenshots
```

Plus [Claude Code](https://claude.ai/claude-code), Python 3.8+, and git 2.28+. The `render login` token expires, so also create a long-lived API key (Render Dashboard → Account Settings → API Keys) and have it ready — the wizard asks for it and stores it gitignored.

### Step 1: Clone the factory (once)

```bash
git clone https://github.com/nbdesai1992/software-factory.git
```

Keep this somewhere permanent. It's the source — you'll point it at each new project.

### Step 2: Onboard a new project

```bash
python /path/to/software-factory/onboard.py ~/code/my-new-app
```

The directory doesn't need to exist — the wizard offers to create it. It asks about your stack (Next.js? FastAPI? PostgreSQL? Clerk?), detects the Render workspace your CLI is logged in to and offers to pin the project to it, then installs everything: 8 skills, 3 worker agents, CLAUDE.md, render.yaml, settings.json, hooks, and skeleton `backend/` + `frontend/` apps. Finally it runs `git init` and — if the `gh` CLI is authenticated — offers to create the GitHub repo, commit, and push. Point it at an existing clone instead and it leaves your repo and remote untouched.

### Step 3: Set up Render (one-time, in the Dashboard)

1. **Env group** — create `general_builder_keys` (or the name you chose) and add shared keys such as `ANTHROPIC_API_KEY`.
2. **Clerk keys** (if you chose Clerk) — create the Clerk app and have its publishable + secret keys ready.
3. **Blueprints → New Blueprint Instance → select your repo.** Render reads `render.yaml` and creates the API service, frontend service, and Postgres database. The skeleton apps deploy on the first build; both `/health` endpoints should return `{"status": "ok"}`.
4. Set the `sync: false` env vars (Clerk keys) on the new services.

Render cannot create Blueprint Instances from the API or CLI, so this step is always yours. The infra worker verifies the services exist and uses them; it never creates them.

### Step 4: Preflight, then build

```bash
python3 .claude/scripts/preflight.py   # tools, git, Render credential, workspace, services, secrets — fix every FAIL
claude                                  # Open Claude Code in your project

# Inside Claude Code:
/preflight                              # same check, explained
/spec create "build an invoice tracker for freelancers"
# Answer a few questions about features, scope, constraints...
# The spec skill writes the brief and hands you a /goal prompt — paste it:
/goal Brief 001-invoice-tracker ... is in a terminal folder ...
# The factory takes over: infra → backend → frontend → deploy, turn after turn
/status
# Check the board at any time
```

The runner provisions infrastructure, writes backend code tested against your real Render database, builds the frontend wired to the deployed API, and parks anything that needs you (like `git push` to deploy) as a blocker while it finishes everything else. When the brief leaves `2-active/` it lands in exactly one of two places: `4-done/` (complete) or `3-blocked/` (NEEDS HUMAN INTERVENTION — answer the brief's `Resolution:` lines and run `/orchestrate` to resume). Prefer manual control? Skip `/goal` and run `/orchestrate` one turn at a time.

## Architecture

```
          /spec create "..."
                │
                ▼
          ┌───────────┐   Goal brief in briefs/1-backlog/ + /goal prompt
          │   BRIEF    │   (requirements, acceptance criteria, embedded
          └─────┬─────┘    execution protocol, task breakdown, progress log)
                │
          /goal ... (or /orchestrate per turn)
                │
                ▼                        ┌── after each turn, a checker model
       ┌─────────────────┐               │   asks: "brief in a terminal
       │  BOARD RUNNER    │ ◄────────────┘   folder yet?" — no → next turn
       └────────┬────────┘
                │  Task tool (worker subagents, sequential)
     ┌──────────┼──────────┐
     ▼          ▼          ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ backend  │ │ frontend │ │  infra   │
│ worker   │ │ worker   │ │ worker   │
│          │ │          │ │          │
│ Models   │ │ Bold     │ │ Deploy   │
│ APIs     │ │ Design   │ │ Verify   │
│ Tests    │ │ Verify   │ │ Monitor  │
└──────────┘ └──────────┘ └──────────┘
     │          │          │
     ▼          ▼          ▼
  Real DB    Screenshots   Render          Terminal: briefs/4-done/  (complete)
  on Render  + iteration   auto-deploy         or briefs/3-blocked/  (needs human)
```

**Infrastructure-first:** Cloud services are provisioned first. Backend develops and tests against the real Render database. Frontend wires to the deployed API. You `git push` to deploy — a natural checkpoint for code review.

**Sequential delegation:** The runner executes subtasks one at a time via native subagents (Task tool). Each worker gets fresh context with its role's skills preloaded, returns a structured report, and the runner records results in the brief.

**Harness-enforced, not remembered:** `/goal` enforces the loop (an independent checker model decides completion), a Stop hook enforces per-turn progress documentation in the brief, and a PostToolUse hook writes a deterministic trajectory log for evals. A generous turn cap in the goal is the only backstop — long-running is fine, infinite is not.

**Resumable by design:** The brief carries all state. Close Claude Code mid-run, reopen, run `/orchestrate` — it reads the board and picks up exactly where it left off.

## Commands

| Command | Description |
|---------|-------------|
| `/preflight` | Readiness check: tools, git remote, Render credential + workspace, services/database/env group vs `render.yaml`, secrets |
| `/spec create "goal"` | Interview → goal brief in `1-backlog/` + ready-to-paste `/goal` prompt |
| `/spec update {id}` | Modify a brief's requirements (active briefs re-plan next turn) |
| `/spec show` | Render the board; add a brief ID for its full detail |
| `/goal <generated prompt>` | Autonomous: run turns until the brief reaches `4-done/` or `3-blocked/` |
| `/orchestrate` | Run the board one turn manually (also resumes blocked briefs after you answer) |
| `/status` | Board summary |
| `/status detail` | Active brief's full task breakdown |
| `/status blockers` | Open questions needing your input |
| `/status requirements` | Requirement → subtask coverage map |

## Deploy Platform

**Render only.** The factory ships one adapter: CLI reference, API docs, blueprint schema, pricing guide, starter `render.yaml` generation (monorepo with `rootDir` per service), and a fail-closed hook that pins every project to one Render workspace. The onboarding wizard offers `render` or `none`; nothing else is wired up.

To add a platform later: `factory/templates/skills/deploy/{platform}/SKILL.md.tpl` plus a choice in `onboard.py`.

## Human In The Loop

The system is autonomous but pauses for you when it matters:

| When | What You Do | Time |
|------|------------|------|
| Push to deploy | Review code, `git push` | 1-2 min |
| Missing API keys | Set env vars in Render Dashboard | 5 min |
| Brief lands in `3-blocked/` | Answer the `Resolution:` lines in the brief, run `/orchestrate` | 1-5 min |
| Design review (optional) | Check `session/design-direction.md` | 5 min |

A brief in `3-blocked/` means the runner did everything it could and what remains needs you — it is a distinct terminal state, never reported as "done."

Full guide: [docs/HUMAN-INTERVENTION-GUIDE.md](docs/HUMAN-INTERVENTION-GUIDE.md)

## Re-Onboarding

```bash
python /path/to/software-factory/onboard.py --reconfigure
```

Re-reads saved config, lets you change settings, re-generates all files.
