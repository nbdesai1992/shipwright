# Setup Guide

Step-by-step instructions for creating a new project with Software Factory.

## Prerequisites

Once per machine:

| Tool | Install | Why |
|------|---------|-----|
| [Claude Code](https://claude.ai/claude-code) | per its docs | runs the factory |
| Python 3.8+ and git 2.28+ | usually present | onboarding script; `git init -b main` |
| [Render CLI](https://docs.render.com/cli) | `brew install render` then `render login` | infra worker deploys, reads logs, sets env vars |
| [GitHub CLI](https://cli.github.com) | `brew install gh` then `gh auth login` | onboarding creates + pushes the repo (optional, but the smooth path) |
| [dev-browser](https://github.com/sawyerhood/dev-browser) | `npm install -g dev-browser` (then `dev-browser install` if it cannot find Chrome) | frontend worker screenshots the UI |

Accounts: Render (a workspace with billing set up — the generated blueprint uses paid `starter` services and a `basic-256mb` database), GitHub, and Clerk if you want auth.

Verify Render is ready:
```bash
render workspace current -o json
```
This must print your workspace name and `tea-...` ID. A `401 Unauthorized` means the stored token has expired — run `render login` again.

### Render API key (recommended)

`render login` stores a token in `~/.render/cli.yaml` that **expires** after a while. Autonomous runs can outlive it, and then every Render command blocks mid-brief. A long-lived API key avoids that:

1. Render Dashboard → **Account Settings → API Keys → Create API Key**
2. Paste it when the onboarding wizard asks (input is hidden). It goes into `.claude/settings.local.json` as `{"env": {"RENDER_API_KEY": "rnd_..."}}` — gitignored, and Claude Code injects it into every Bash call and hook in the project.
3. Already onboarded? Add it to that file by hand, or `export RENDER_API_KEY=rnd_...` in your shell profile.

Every Render call in the factory resolves the key through `.claude/scripts/render-api-key.sh` (environment → settings.local.json → `.env` → login token), so the CLI, direct API calls, and the workspace guard all use the same credential. Keys are per user; the guard still checks that the key can see the pinned workspace.

## Step 1: Run the Factory Onboarding

Point the onboarding script at a project directory. It does not have to exist yet — you'll be asked whether to create it:

```bash
python /path/to/software-factory/onboard.py ~/code/your-project
```

The wizard asks about your project (name, description, domain, design direction, tech stack, auth). Render is the only deployment platform; the wizard reads the workspace your Render CLI is logged in to and offers to pin the project to it (name and ID — every Render command is blocked outside that workspace). Then it installs everything:

- `backend/` — Skeleton FastAPI app with `/health` endpoint
- `frontend/` — Skeleton Next.js app with `/api/health` route
- `.claude/skills/` — 8 pre-built skills (orchestration, testing, design, deployment, etc.)
- `.claude/agents/` — 3 worker agent definitions (backend, frontend, infra)
- `.claude/settings.json` — Permissions + hook wiring
- `.claude/hooks/` — brief-progress-guard, trajectory-log, render-workspace-guard
- `.claude/scripts/` — `render-api-key.sh` (credential resolver) and `preflight.py` (readiness check)
- `.claude/render-workspace` — the workspace pin
- `.claude/settings.local.json` — your `RENDER_API_KEY` if you provided one (gitignored)
- `CLAUDE.md` — Project context, architecture, deployed URLs
- `render.yaml` — Render blueprint defining your services + database
- `.gitignore` — `session/`, `.env`, `.env.local`, `.claude/settings.local.json`, `.claude/.turn-marker`

Finally it sets up git: `git init`, then — if the `gh` CLI is installed and authenticated — offers to create a GitHub repo, wire it up as `origin`, commit the setup, and push. Decline any of these and it prints the command to run yourself. Render's GitHub integration detects `render.yaml` as soon as the push lands.

Already have a repo cloned? Just run `python /path/to/software-factory/onboard.py` from inside it — the existing git repo and remote are left alone.

## Step 2: Create Env Group + Blueprint Instance

### 2a: Create shared env group (one-time per workspace)

If you don't already have a `general_builder_keys` env group in your Render workspace:

1. Render Dashboard → **Env Groups** → **New Environment Group**
2. Name it `general_builder_keys` (or whatever you specified during onboarding)
3. Add your shared API keys (e.g., `ANTHROPIC_API_KEY`)

The `render.yaml` references this group via `fromGroup` — all services will automatically receive these keys when the blueprint is applied.

### 2b: Create Clerk application (if auth is configured)

If you chose Clerk during onboarding:

1. Go to [clerk.com](https://clerk.com) → sign in → **Create Application**
2. Name it after your project
3. Copy the **Publishable Key** and **Secret Key**
4. In the Render Dashboard, set these env vars on your services:
   - Frontend: `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` = your publishable key
   - Frontend: `CLERK_SECRET_KEY` = your secret key
   - Backend: `CLERK_SECRET_KEY` = your secret key

These are declared as `sync: false` in render.yaml — you set the values manually.

### 2c: Apply Blueprint Instance

This is a one-time manual step. Render does not support creating Blueprint Instances via API or CLI — it must be done in the Dashboard.

1. Go to [Render Dashboard](https://dashboard.render.com/)
2. **Select the correct workspace** (not a shared/team workspace unless intended)
3. **Blueprints** → **New Blueprint Instance**
4. Select your GitHub repo and the branch you're deploying from (e.g., `develop` or `main`)
5. Render reads `render.yaml` and creates:
   - `{your-project}-api` (backend web service, Python/FastAPI)
   - `{your-project}-frontend` (frontend web service, Node/Next.js)
   - `{your-project}-db` (PostgreSQL database)
   - Links the shared env group to both services
   - Sets cross-service URLs (`API_URL` on frontend, `FRONTEND_URL` + `CORS_ORIGINS` on backend)
6. First deploy will build and deploy the skeleton apps. Both `/health` endpoints should return `{"status": "ok"}`.

**Important:** The infra-worker will never create services via API. It only verifies that services exist (created by you here) and uses them for deployments, logs, and health checks. If you skip this step, the orchestrator will raise a blocker asking you to do it.

## Step 3: Preflight

```bash
python3 .claude/scripts/preflight.py      # from the project directory
```

One line per check, `[PASS]` / `[WARN]` / `[FAIL]`, with a fix under every FAIL. It covers local tools (render, gh, dev-browser, node), the git remote, the Render credential and whether it has expired, the workspace pin, and then compares `render.yaml` against live Render: env group present, every service and database exists, `sync: false` secrets have values, health endpoints answer. It changes nothing.

Fix every FAIL before continuing. WARNs are informational (unpushed commits, URLs the infra-worker will fill in). The runner also runs this check automatically the first time it pulls a brief, and parks any FAIL as a blocker instead of spawning a worker into a wall. Inside Claude Code the same check is `/preflight`.

## Step 4: Open Claude Code

```bash
claude
```

Open Claude Code in your project directory. It will load CLAUDE.md and all the installed skills.

## Step 5: Create a Goal Brief

```
/spec create "describe what you want to build"
```

The spec skill interviews you about features, scope, constraints, and success criteria, then writes a goal brief to `briefs/1-backlog/` and hands you a ready-to-paste `/goal` prompt. Review and approve the brief.

## Step 6: Run It

Paste the `/goal` prompt the spec skill gave you — Claude Code keeps running turns until the brief reaches a terminal folder (`briefs/4-done/` complete, or `briefs/3-blocked/` needs your input). Or run one turn at a time:

```
/orchestrate
```

Either way, the runner takes over:

1. **Infrastructure** — Verifies Render services exist, pulls DB credentials into `backend/.env`
2. **Backend** — Writes models, migrations, API endpoints, tests against real Render DB
3. **Deploy backend** — Commits code, asks you to `git push` (your review checkpoint). Render auto-deploys.
4. **Frontend** — Writes UI with domain-specific design, wired to deployed backend API
5. **Deploy frontend** — Commits code, asks you to `git push`. Render auto-deploys.
6. **Verify** — Screenshots the deployed site, checks against requirements

## Step 7: Check Progress

At any time:

```
/status              # Board summary
/status detail       # Active brief's full task breakdown
/status blockers     # What needs your input
/status requirements # Requirement → subtask coverage
```

## When the System Needs You

The runner parks anything that needs a human and keeps working on everything else. When nothing runnable remains, the brief moves to `briefs/3-blocked/` and the runner announces **NEEDS HUMAN INTERVENTION** — a distinct terminal from done, never reported as success.

| When | What to do |
|------|-----------|
| **Push to deploy** | Review the diff, run `git push` (Render auto-deploys on commit) |
| **Missing env var** | Set it in Render Dashboard |
| **Unclear requirement / decision needed** | Open the blocked brief, write your answer on the blocker's `Resolution:` line |
| **Design review** (optional) | Check `session/design-direction.md` after first frontend task |

After answering, run `/orchestrate` — the brief moves back to `2-active/` and work resumes with your answers applied.

## Re-Onboarding

To change your project's configuration later:

```bash
python /path/to/software-factory/onboard.py --reconfigure
```

## Diagnostic: Trajectory

Each brief gets `session/{brief-id}/trajectory.md` — the curated agentic trace written by the runner and workers — plus `session/{brief-id}/trajectory.jsonl`, a deterministic machine-parseable log written automatically by a PostToolUse hook for every subagent call. Use these for evaluating harness behavior and diagnosing issues.
