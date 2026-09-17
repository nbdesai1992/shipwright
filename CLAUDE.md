# Software Factory

A Claude Code orchestration toolkit that turns a product spec into working software.

## What This Is

This repository contains the generic orchestration system — skills, agents, and templates that can be installed into any project. It is NOT a project itself; it is tooling.

## The Contract (do not break this)

1. **Clone this repo.**
2. **Run the wizard** (`bootstrap.sh` → `onboard.py`).
3. **A new project repo exists**: one monorepo (`backend/` + `frontend/`), pushed to GitHub, with its Render database and web services live, and Claude Code configured inside it.

Every change to the factory is measured against those three steps. Nothing may become a per-project manual prerequisite between them — no Dashboard clicking, no file editing, no "first go create X". The only manual setup allowed is account-level and one-time (Render payment method, Render↔GitHub connection, Render API key, optional Clerk app), and it is documented in GETTING-STARTED.md. If a new feature needs something from the human, it is asked for in the wizard or reported by `preflight.py` with a fix line; if a script can do it, a script does it (`provision.py` creates Render resources — the Blueprint Instance is optional).

Two wizard modes share one code path: **Quick Start** (default; four questions, all defaults, runner pushes, plain-language runner) and **Custom** (developer chooses). Both must keep the contract.

## Repository Structure

```
software-factory/
├── bootstrap.sh            # macOS: install tools, log in, launch onboard.py
├── onboard.py              # Interactive setup wizard (Quick Start | Custom) — entry point
├── GETTING-STARTED.md      # Non-developer walkthrough (the contract, step by step)
├── SETUP.md                # Developer setup guide
├── factory/
│   ├── skills/             # Generic skills (copied as-is to target projects)
│   │   ├── orchestrate/    # Decompose specs → spawn workers → track progress
│   │   ├── worker-protocol/# Shared worker conventions
│   │   ├── backend-test/   # TDD flow for backend work
│   │   ├── bold-design/    # Domain-specific UI design (reads CLAUDE.md at runtime)
│   │   ├── spec/           # Spec creation and management
│   │   └── status/         # Session diagnostic
│   └── templates/          # Customizable templates (rendered with project config)
│       ├── CLAUDE.md.tpl
│       ├── settings.json.tpl   # Permissions + hook wiring
│       ├── briefs-README.md    # Brief board README (copied to briefs/)
│       ├── hooks/          # brief-progress-guard.sh, trajectory-log.sh, render-workspace-guard.sh
│       ├── scripts/        # render-api-key.sh (credential), render_yaml.py (shared reader),
│       │                   #   preflight.py.tpl (readiness), provision.py.tpl (apply render.yaml via API)
│       ├── agents/         # Worker subagent definitions
│       └── skills/         # Skills that need project context
│           ├── verify-ui/  # Screenshot verification (needs server config)
│           ├── preflight/  # /preflight — wraps scripts/preflight.py
│           └── deploy/     # Platform adapters (render, etc.)
└── docs/
    ├── HUMAN-INTERVENTION-GUIDE.md
    └── decisions.md        # Factory-level decision log
```

## How to Use

1. Clone this repo
2. From your target project directory: `python /path/to/software-factory/onboard.py`
3. Answer the questions
4. Open Claude Code in your project
5. `/spec create "what you want to build"` — produces a goal brief + a `/goal` prompt
6. Paste the `/goal` prompt (autonomous) or run `/orchestrate` one turn at a time

## Development Guidelines

- Generic skills should contain NO project-specific content (stack-level references to Render, render.yaml, and Clerk are accepted in V1 — the factory is Render-only)
- Templates use `{{PLACEHOLDER}}` syntax (simple string replacement, no Jinja2)
- Render is the only deploy platform. The onboarding wizard offers `render` or `none`; a new adapter needs `factory/templates/skills/deploy/{platform}/SKILL.md.tpl` AND a wizard choice in `onboard.py`
- Hooks installed into projects are listed explicitly in `HOOK_FILES` in `onboard.py` (must match `settings.json.tpl`) — never glob the templates folder
- Third-party runtime dependency: `dev-browser` (frontend screenshots). Prerequisites are documented in SETUP.md; keep them in sync when adding a dependency
- Render credentials: every CLI/API snippet resolves the key via `.claude/scripts/render-api-key.sh` (env → settings.local.json → .env → login token). Never hardcode `~/.render/cli.yaml` parsing in a skill again, and never write a key into a committed file
- Readiness checks belong in `scripts/preflight.py.tpl` (deterministic, stdlib only), not in skill prose. New "the human must do X first" requirements get a preflight check plus a fix hint
- Render resources are created only by `scripts/provision.py.tpl`, which applies `render.yaml`. Skills and agents never hand-craft create calls and never ask a human to click in the Dashboard for something the provisioner can do. New resource types go into the provisioner and the shared `render_yaml.py` reader together
- Mode-dependent behavior is expressed as config values rendered into templates (`{{MODE_SECTION}}`, `{{PUSH_POLICY_LINE}}`, `{{QUICKSTART_PERMISSIONS}}`), never as separate template sets
- The runner delegates subtasks to native worker subagents (Task tool, one at a time, sequential); agent definitions live in `.claude/agents/` with skills preloaded via their `skills:` frontmatter
- Target projects get a committed `briefs/` Kanban board (1-backlog / 2-active / 3-blocked / 4-done — folder location is status) plus hooks in `.claude/hooks/` that enforce per-turn brief documentation and deterministic trajectory logging
