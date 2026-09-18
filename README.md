# Software Factory

**Prompt to production.** A Claude Code orchestration toolkit with pre-built skills, worker agents, and deployment configs that turns a product description into deployed, tested software — autonomously.

## The Contract

1. **Clone this repo.**
2. **Open Claude Code in it and type `/start`.** Claude checks the machine, installs what's missing, walks through GitHub and Render account setup one step at a time, asks four questions, and runs the wizard. (Developers can run `onboard.py` directly instead.)
3. **A new project repo is created** — one monorepo with `backend/` + `frontend/`, pushed to GitHub, with its database and web services live on Render, and Claude Code configured inside it to build what you describe.

Nothing else is a prerequisite: Claude Code is the only thing that must already be installed. No Dashboard clicking per project — the wizard provisions Render from `render.yaml` through the API. The one-time account setup (Render payment method, Render↔GitHub connection, Render API key) is walked through by `/start` and written down in [GETTING-STARTED.md](GETTING-STARTED.md).

Then, inside the new project:

```
/spec create "build an invoice tracker for freelancers"
/goal <the prompt the spec skill hands you>
```

The factory handles decomposition, coding, testing, visual design, and deployment across backend, frontend, and infrastructure — with you in the loop only when it matters.

**Two modes**, same machinery. **Quick Start** (default) asks four plain questions, takes every technical default, lets the runner push deploys, and tells every session to speak in plain language and take decisions from chat. **Custom** asks the developer questions: stack, auth, env group, who pushes.

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

1. **Onboard** — Run the setup wizard, pointed at a project directory (existing or not). Four questions in Quick Start, the full stack interview in Custom. The factory creates the repo, installs skills, agents, hooks, and the brief board, pushes it to GitHub, and provisions the Render database and services from `render.yaml`.
2. **Spec** — Describe what you want. The spec skill interviews you and produces a **goal brief**: a self-contained card on the `briefs/` Kanban board with requirements, acceptance criteria, and an embedded execution protocol — plus a ready-to-paste `/goal` prompt.
3. **Run** — Paste the `/goal` prompt. Claude Code keeps running turns until the brief reaches a terminal folder; each turn the runner delegates subtasks to specialized worker subagents, updates the brief, and proves board state. Human blockers are parked while everything else continues — the brief only lands in `3-blocked/` when nothing runnable remains.
4. **Deploy** — Infrastructure-first workflow. Backend deploys and tests against a real database before frontend work begins. Render auto-deploys on push; in Quick Start the runner pushes, in Custom you choose who does.

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
    ├── scripts/            # render-api-key.sh (credential), preflight.py (readiness),
    │                       #   provision.py (applies render.yaml via the Render API)
    ├── render-services.json# live ids + URLs, written by provision.py
    ├── agents/             # 3 worker subagent definitions
    └── skills/             # 9 skills (orchestration + development + deployment + preflight)
```

## Usage

Non-developers: follow [GETTING-STARTED.md](GETTING-STARTED.md). Developers, the short version:

### Once per machine and per Render account

```bash
git clone https://github.com/nbdesai1992/software-factory.git ~/software-factory
```

Render Dashboard, one time: add a **payment method** (Billing), **connect GitHub** (Account Settings → GitHub), and create an **API key** (Account Settings → API Keys). Store the key once, machine-wide:

```bash
python3 ~/software-factory/onboard.py --set-render-key     # → ~/.claude/settings.json env block
```

That is the only Render credential the factory uses — CLI, API calls, hooks, every project. `render login` is never required (its browser token expires; it remains a fallback).

### Step 1–3: clone → `/start` (or the wizard directly) → new repo

```bash
cd ~/software-factory && claude        # then type /start — Claude drives everything below
# or, developers, run the wizard yourself:
python3 ~/software-factory/onboard.py ~/code/my-new-app [--quick|--custom]
# or fully non-interactive:
python3 ~/software-factory/onboard.py ~/code/my-new-app --quick --yes --name "My App" --description "..." --domain "..." --login no
```

Tools the wizard needs: `gh` (repo creation + git auth), `node` + `dev-browser` (local screen previews). `/start` installs them; the Render CLI is optional.

The directory doesn't need to exist. The wizard asks its questions (four in Quick Start; stack, auth, env group and push policy in Custom), pins the project to the Render workspace your CLI is logged in to, installs everything — 9 skills, 3 worker agents, CLAUDE.md, render.yaml, settings.json, hooks, scripts, skeleton `backend/` + `frontend/` apps — then creates the GitHub repo, commits, pushes, and **runs `provision.py`**, which creates the database and both web services on Render from `render.yaml`. When it returns you have a monorepo on GitHub with two `onrender.com` URLs serving the skeleton. Point it at an existing clone instead and it leaves your repo and remote untouched.

`provision.py` is idempotent and is also how the infra-worker applies later changes to `render.yaml`. A human-created Blueprint Instance is an optional alternative applier for developers who want Render's native sync; nothing requires it.

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

**Render only.** The factory ships one adapter: CLI reference, API docs, blueprint schema, pricing guide, starter `render.yaml` generation (monorepo with `rootDir` per service), `provision.py` to apply that file through the API, and a fail-closed hook that pins every project to one Render workspace. The onboarding wizard offers `render` or `none`; nothing else is wired up.

To add a platform later: `factory/templates/skills/deploy/{platform}/SKILL.md.tpl` plus a choice in `onboard.py`.

## Human In The Loop

The system is autonomous but pauses for you when it matters:

| When | What You Do | Time |
|------|------------|------|
| Push to deploy (Custom mode, `human` push policy) | Review code, `git push` | 1-2 min |
| Missing API keys | `python3 .claude/scripts/provision.py --set KEY=VALUE` | 1 min |
| Brief lands in `3-blocked/` | Answer the `Resolution:` lines in the brief, run `/orchestrate` | 1-5 min |
| Design review (optional) | Check `session/design-direction.md` | 5 min |

A brief in `3-blocked/` means the runner did everything it could and what remains needs you — it is a distinct terminal state, never reported as "done."

Full guide: [docs/HUMAN-INTERVENTION-GUIDE.md](docs/HUMAN-INTERVENTION-GUIDE.md)

## Re-Onboarding

```bash
python /path/to/software-factory/onboard.py --reconfigure
```

Re-reads saved config, lets you change settings, re-generates all files.
