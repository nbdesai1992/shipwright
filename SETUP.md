# Setup Guide (developers)

Step-by-step instructions for creating a new project with Consul. Non-developers: use [GETTING-STARTED.md](GETTING-STARTED.md) instead — same result, plainer words.

The contract: **clone this repo → run the wizard → a new project repo exists**, on GitHub, with its Render database and services live. Everything below serves those three steps.

## Prerequisites

Once per machine:

| Tool | Install | Why |
|------|---------|-----|
| [Claude Code](https://claude.ai/claude-code) | per its docs | runs Consul |
| Python 3.8+ and git 2.28+ | usually present | onboarding script; `git init -b main` |
| [Render CLI](https://docs.render.com/cli) | optional (`brew install render`) | convenience only — every operation has an API equivalent and Consul uses the API |
| [GitHub CLI](https://cli.github.com) | `brew install gh` then `gh auth login` | onboarding creates + pushes the repo (optional, but the smooth path) |
| [dev-browser](https://github.com/sawyerhood/dev-browser) | `npm install -g dev-browser` (then `dev-browser install` if it cannot find Chrome) | frontend worker screenshots the UI |

Or open Claude Code in your Consul clone and type `/start`: it checks for all of the above, installs what's missing, walks through the account steps, and drives the wizard non-interactively.

Accounts, one-time:
- **GitHub.**
- **Render** — three things in the Dashboard before the first project: a **payment method** (Billing; the generated blueprint uses paid `starter` services and a `basic-256mb` database, ≈ $20/month per project), **GitHub connected** (Account Settings → GitHub; Render must be able to read the repo the wizard creates), and an **API key** (next section).
- **Clerk**, if you want auth. Create the application before running the wizard so you can paste its publishable + secret keys when asked; the provisioner sets them on the services.

### Render API key (the credential)

Consul authenticates to Render with a long-lived **API key**, never with the browser login. `render login` writes a token that expires after a few weeks and silently breaks autonomous runs; the API key does not expire.

1. Render Dashboard → your avatar → **Account Settings → API Keys → Create API Key**
2. Store it once, machine-wide:
   ```bash
   python3 ~/consul/onboard.py --set-render-key
   ```
   It goes into the `env` block of `~/.claude/settings.json`. Claude Code injects that block into every session; the Render CLI honors `RENDER_API_KEY`; Consul's resolver reads it. `/start` asks for it if it is missing.
3. Per-project override, if you ever need one: `.claude/settings.local.json` `{"env": {"RENDER_API_KEY": "rnd_..."}}` (gitignored). The wizard copies the machine key there so each project is self-contained.

Every Render call in Consul resolves the key through `.claude/scripts/render-api-key.sh` (environment → project settings.local.json → project `.env` → `~/.claude/settings.json` → login token), so the CLI, direct API calls, the provisioner, and the workspace guard all use the same credential. The workspace pin comes from the key's visible workspaces (or the CLI login if one exists); with several workspaces the wizard asks which one.

## Step 1: Run the Consul wizard

Point the onboarding script at a project directory. It does not have to exist yet — you'll be asked whether to create it:

```bash
python /path/to/consul/onboard.py ~/code/your-project
```

First question: **Quick Start or Custom.** Quick Start asks four plain questions (name, one sentence, who it's for, sign-in yes/no) and takes every default: Next.js + FastAPI + PostgreSQL on Render, no env group, runner pushes deploys, plain-language runner. Custom asks about stack, auth, env group, and push policy. Both pin the project to the Render workspace your CLI is logged in to (name and ID — every Render command is blocked outside that workspace) and ask for the Render API key and, if Clerk, its two keys (hidden input, stored gitignored). Then the wizard installs everything:

- `backend/` — Skeleton FastAPI app with `/health` endpoint
- `frontend/` — Skeleton Next.js app with `/api/health` route
- `.claude/skills/` — 8 pre-built skills (orchestration, testing, design, deployment, etc.)
- `.claude/agents/` — 3 worker agent definitions (backend, frontend, infra)
- `.claude/settings.json` — Permissions + hook wiring
- `.claude/hooks/` — brief-progress-guard, trajectory-log, render-workspace-guard
- `.claude/scripts/` — `render-api-key.sh` (credential resolver), `preflight.py` (readiness check), `provision.py` (applies render.yaml to Render)
- `.claude/render-workspace` — the workspace pin
- `.claude/settings.local.json` — your `RENDER_API_KEY` if you provided one (gitignored)
- `CLAUDE.md` — Project context, architecture, deployed URLs
- `render.yaml` — Render blueprint defining your services + database
- `.gitignore` — `session/`, `.env`, `.env.local`, `.claude/settings.local.json`, `.claude/.turn-marker`

Then git: `git init`, create the GitHub repo via `gh` (default yes), commit, push. Decline any of these and it prints the command to run yourself.

Already have a repo cloned? Just run `python /path/to/consul/onboard.py` from inside it — the existing git repo and remote are left alone.

## Step 2: Live services — the wizard provisions Render

Right after the push, the wizard runs `.claude/scripts/provision.py`. It reads `render.yaml` and creates, through the Render API in the pinned workspace:

- `{slug}-db` (PostgreSQL, `basic-256mb`, external access opened so local backend tests can reach it)
- `{slug}-api` (Python web service, `rootDir: backend`, `DATABASE_URL` wired from the database)
- `{slug}-frontend` (Node web service, `rootDir: frontend`)
- any env group referenced by `fromGroup` (created empty if missing, then linked)
- cross-service URLs (`API_URL`, `NEXT_PUBLIC_API_URL`, `FRONTEND_URL`, `CORS_ORIGINS`) from the real `onrender.com` hostnames
- Clerk keys on the services, if you supplied them
- `backend/.env` with the external `DATABASE_URL` (gitignored), and `.claude/render-services.json` with ids and URLs

The skeleton apps deploy on the first build; both `/health` endpoints return `{"status": "ok"}` a few minutes later. Nothing to click in the Render Dashboard.

```bash
python3 .claude/scripts/provision.py --dry-run          # see the plan
python3 .claude/scripts/provision.py                    # apply (asks once; paid resources start billing)
python3 .claude/scripts/provision.py --set CLERK_SECRET_KEY=sk_...   # add a secret later
```

It is idempotent: re-run it after editing `render.yaml` and it creates only what is missing. It never deletes and never overwrites a value you set, except the derived URL keys. To spin a project down, `provision.py --destroy` deletes its declared services and databases after you type the slug (env groups are left alone). The GitHub repo is separate: `gh repo delete <owner>/<slug> --yes` needs the `delete_repo` scope (`gh auth refresh -h github.com -s delete_repo` once), or delete it in the GitHub UI. This is also what the infra-worker runs as the first task of every brief, and what preflight tells you to run when something is missing.

**If it fails**, the `[FAIL]` line says why. The three real causes: no payment method on the workspace (402/403), Render cannot read the repo (connect GitHub in Render → Account Settings → GitHub and grant access to the new repo), or an expired credential (`render login`, or a fresh API key).

**Prefer Render's own Blueprint?** Dashboard → Blueprints → New Blueprint Instance → select the repo. It reads the same `render.yaml` and the two appliers coexist; the provisioner will find the blueprint-created resources by name and leave them alone. This is optional.

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

1. **Infrastructure** — Runs `provision.py` (idempotent), audits live Render state against `render.yaml`, verifies the database is reachable from `backend/.env`
2. **Backend** — Writes models, migrations, API endpoints, tests against real Render DB
3. **Deploy backend** — Commits code. Push policy `human`: asks you to `git push` (review checkpoint). Push policy `consul` (Quick Start default): the runner pushes. Render auto-deploys.
4. **Frontend** — Writes UI with domain-specific design, wired to deployed backend API
5. **Deploy frontend** — Same push policy. Render auto-deploys.
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
| **Push to deploy** (push policy `human`) | Review the diff, run `git push` (Render auto-deploys on commit) |
| **Missing env var / secret** | `python3 .claude/scripts/provision.py --set KEY=VALUE` |
| **Unclear requirement / decision needed** | Open the blocked brief, write your answer on the blocker's `Resolution:` line |
| **Design review** (optional) | Check `session/design-direction.md` after first frontend task |

After answering, run `/orchestrate` — the brief moves back to `2-active/` and work resumes with your answers applied.

## Re-Onboarding

To change your project's configuration later:

```bash
python /path/to/consul/onboard.py --reconfigure
```

## Diagnostic: Trajectory

Each brief gets `session/{brief-id}/trajectory.md` — the curated agentic trace written by the runner and workers — plus `session/{brief-id}/trajectory.jsonl`, a deterministic machine-parseable log written automatically by a PostToolUse hook for every subagent call. Use these for evaluating harness behavior and diagnosing issues.
