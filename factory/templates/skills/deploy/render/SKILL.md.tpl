---
name: deploy
description: Manage all Render infrastructure — services, databases, Redis, cron jobs, deployments, logs, env vars, and IaC blueprints. Use when working with Render in any capacity (deploying, debugging, provisioning, monitoring).
allowed-tools: Bash, Read, Write, Edit
argument-hint: "[logs|deploy|status|create|blueprint|help]"
---

# Render Operations Guide

**CLI constraint:** Always use `-o json` or `-o text` — interactive mode doesn't work in this shell.

## Pre-Flight: Verify Workspace

The ONLY authorized workspace for this project is **{{RENDER_WORKSPACE}}** (ID: `{{RENDER_WORKSPACE_ID}}`). A PreToolUse hook (`render-workspace-guard`) enforces this mechanically: Render CLI/API commands are blocked unless `render workspace current` matches the pin in `.claude/render-workspace`, and `render workspace set` may only target the pinned workspace.

Before ANY Render operation, verify:
```bash
render workspace current -o json
```
If it doesn't match **{{RENDER_WORKSPACE}}**, run `render workspace set {{RENDER_WORKSPACE_SET_TARGET}}`. If that fails (e.g. `401 Unauthorized` — the stored login token has expired), raise an `external-action` blocker asking the human to run `render login`; there is no way to re-authenticate from inside a worker. NEVER operate in any other workspace — services would be created or modified in the wrong account. Do not edit or delete `.claude/render-workspace` to get around a block.

## Authentication: One Resolver, Two Kinds of Credential

Every Render call — CLI or curl — starts with:
```bash
export RENDER_API_KEY=$(.claude/scripts/render-api-key.sh)
```
The `export` matters: the Render CLI also honors `RENDER_API_KEY`, so one line makes both `render services list` and `curl api.render.com` work in the same shell without a fresh `render login`.

The resolver looks, in order, at: `$RENDER_API_KEY` already in the environment (Claude Code injects the `env` block of `.claude/settings.local.json` into every Bash call), `.claude/settings.local.json`, the project `.env`, and finally the `render login` token in `~/.render/cli.yaml`. Only the first three are long-lived; the login token **expires** and a long run can outlive it. `.claude/scripts/render-api-key.sh --source` tells you which one is in use (`cli-token-EXPIRED` means exactly that).

If a call returns `401 Unauthorized`: do not retry, do not try other credentials. Raise an `external-action` blocker: "Render credential expired or missing — run `render login`, or add a long-lived API key (Render Dashboard → Account Settings → API Keys) to the `env` block of `.claude/settings.local.json`." `/preflight` reports this before any run starts.

## render.yaml Is the Source of Truth

`render.yaml` MUST be the **complete, authoritative declaration** of all service configuration:
- Every env var (hardcoded, fromDatabase, fromGroup, or sync: false)
- Every env group link (fromGroup)
- Every runtime setting (buildCommand, startCommand, healthCheckPath, plan)

**If you add a new env var dependency** (e.g., adding an API integration that needs a key):
1. Determine: does this key belong in the shared env group (fromGroup) or as a service-level var?
2. Update render.yaml accordingly — either add the var or confirm it exists in the linked env group
3. If it's a secret, use `sync: false` (value set in Dashboard, not in code)

**Never make manual Dashboard changes without updating render.yaml.** Drift between render.yaml and actual Render state causes silent failures.

## Render State Audit (Phase 1 of every orchestration run)

Before any code work begins, audit the live Render state against render.yaml:

```bash
export RENDER_API_KEY=$(.claude/scripts/render-api-key.sh)   # see "Authentication" below

# 1. Pull actual env vars for each service
curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
  "https://api.render.com/v1/services/<SERVICE_ID>/env-vars"

# 2. Pull linked env groups
curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
  "https://api.render.com/v1/env-groups/<GROUP_ID>"

# 3. Pull service details (runtime, build/start commands)
curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
  "https://api.render.com/v1/services/<SERVICE_ID>"
```

**Compare against render.yaml. Flag as blockers:**
- Missing env vars (declared in render.yaml but not on Render)
- `sync: false` vars with no value set (e.g., `CLERK_SECRET_KEY`, `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` empty — human needs to set them in Dashboard)
- Extra env vars (on Render but not in render.yaml — potential drift)
- Wrong values (version mismatch, incorrect URLs)
- Missing env group links
- Runtime/build/start command mismatch

**Discover and set actual service URLs:**
Render adds random suffixes to URLs (e.g., `{slug}-api-z0l3.onrender.com`). The infra-worker MUST:
1. Get actual URLs from `render services list -o json` (look for the `url` field in serviceDetails)
2. Set cross-service env vars via API with full `https://` URLs:
   ```bash
   # Set API_URL on frontend
   curl -s -H "Authorization: Bearer $RENDER_API_KEY" -H "Content-Type: application/json" \
     -X PUT "https://api.render.com/v1/services/<FRONTEND_ID>/env-vars" \
     -d '[{"key": "API_URL", "value": "https://<actual-backend-url>"}]'

   # Set FRONTEND_URL + CORS_ORIGINS on backend
   curl -s -H "Authorization: Bearer $RENDER_API_KEY" -H "Content-Type: application/json" \
     -X PUT "https://api.render.com/v1/services/<BACKEND_ID>/env-vars" \
     -d '[{"key": "FRONTEND_URL", "value": "https://<actual-frontend-url>"}, {"key": "CORS_ORIGINS", "value": "https://<actual-frontend-url>"}]'
   ```
3. Record the actual URLs in the task file's Interface Contract for downstream workers
4. Update CLAUDE.md's Deployment section with the real URLs

## Known Services

| Service | ID | Type |
|---------|-----|------|
| (none provisioned yet) | — | — |

Update this table as new services are provisioned.

---

## Quick Reference: Everyday Commands

### Status & Logs
```bash
# All services in workspace
render services list -o json

# Logs for a service (last 100)
render logs -r <SERVICE_ID> -o text

# Error logs
render logs -r <SERVICE_ID> -o text --level error --limit 50

# Search logs by text
render logs -r <SERVICE_ID> -o text --text "Error,timeout"

# Time-windowed logs
render logs -r <SERVICE_ID> -o text --start "2026-03-28T00:00:00Z" --end "2026-03-28T12:00:00Z"

# Filter by HTTP status/method/path
render logs -r <SERVICE_ID> -o text --status-code 500,502 --method POST --path "/api"
```

### Deployments
```bash
render deploys list -o json -r <SERVICE_ID>           # List deploys
render deploys create -o json -r <SERVICE_ID> --confirm  # Trigger deploy
render deploys cancel -o json -r <SERVICE_ID>          # Cancel running deploy
```

### Service Management
```bash
render restart -o json -r <SERVICE_ID> --confirm       # Restart
render services instances -o json -r <SERVICE_ID>      # List instances
```

### Workspace
```bash
render workspace current -o json                       # Current workspace
render workspace list -o json                          # List workspaces
```

---

## IMPORTANT: Never Create Services via API

Services are created by the **human** via Render Dashboard → Blueprints → "New Blueprint Instance." This reads `render.yaml` and provisions all services in the correct workspace. The Render API does NOT support creating blueprint instances.

**You MUST NOT** use `POST /v1/services` or `POST /v1/postgres` to create services directly. This bypasses the blueprint, may target the wrong workspace, and creates unlinked services.

Your job is to **verify** services exist (created by the human via blueprint) and **use** them (deploy, logs, env vars, health checks). If services don't exist, raise a blocker asking the human to create the Blueprint Instance.

## When to Use the API Directly

The CLI doesn't cover everything. Use the Render API (`https://api.render.com/v1/`) with the stored API key for:
- Managing env vars and env groups
- Custom domains
- Scaling and autoscaling
- Metrics (CPU, memory, HTTP latency, etc.)
- Querying deploy status and logs

```bash
# Helper: extract API key from CLI config
export RENDER_API_KEY=$(.claude/scripts/render-api-key.sh)   # see "Authentication" below

# Example: list all services
curl -s -H "Authorization: Bearer $RENDER_API_KEY" https://api.render.com/v1/services

# Example: list env vars for a service
curl -s -H "Authorization: Bearer $RENDER_API_KEY" https://api.render.com/v1/services/<SERVICE_ID>/env-vars
```

For the full API reference, see [api-reference.md](api-reference.md).

---

## Infrastructure as Code: render.yaml

The project should use a `render.yaml` blueprint at the repo root. This declares all services, databases, env groups, and their configuration as code.

### When to use render.yaml
- Spinning up a new service (don't create manually in Dashboard)
- Adding a database or Redis instance
- Configuring env var groups shared across services
- Ensuring reproducible infrastructure

### Quick example
```yaml
services:
  - type: web
    name: {{PROJECT_SLUG}}
    runtime: node
    plan: starter
    region: oregon
    buildCommand: npm install
    startCommand: npm start
    healthCheckPath: /health
    envVars:
      - key: NODE_ENV
        value: production
      - fromGroup: shared-config

databases:
  - name: {{PROJECT_SLUG}}-db
    plan: starter
    region: oregon
    postgresMajorVersion: 16

envVarGroups:
  - name: shared-config
    envVars:
      - key: LOG_LEVEL
        value: info
```

For the full blueprint schema, service types, and advanced patterns, see [blueprint-reference.md](blueprint-reference.md).

---

## Service Types: Which to Use When

| Type | Blueprint `type` | Public URL | Traffic | Use case |
|------|------------------|------------|---------|----------|
| Web Service | `web` | Yes | HTTP from internet | API servers, web apps |
| Private Service | `pserv` | No | Internal only | Internal APIs, microservices |
| Background Worker | `worker` | No | None | Queue processing, async tasks |
| Cron Job | `cron` | No | None | Scheduled tasks (12hr max) |
| Static Site | `web` + `runtime: static` | Yes (CDN) | HTTP | SPAs, marketing sites |
| PostgreSQL | under `databases:` | No | Connection string | Relational database |
| Key Value | `keyvalue` | No | Connection string | Redis caching, sessions, queues |

---

## Post-Push Deploy Verification

**CRITICAL: A health endpoint returning 200 does NOT mean the latest code is deployed.** Render uses zero-downtime deploys — when a new deploy fails, the OLD deploy keeps running. The health check hits the old code. You MUST check the deploy status itself.

### Verification sequence (for EVERY service after a push):

```bash
export RENDER_API_KEY=$(.claude/scripts/render-api-key.sh)   # see "Authentication" below

# 1. Get the latest deploy — check status AND commit SHA
curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
  "https://api.render.com/v1/services/<SERVICE_ID>/deploys?limit=1"

# Look at:
#   "status": must be "live" (not "build_failed", "update_failed", "build_in_progress")
#   "commit.id": must match the commit you just pushed
```

### Decision tree:

| Deploy status | Commit matches? | Action |
|--------------|----------------|--------|
| `live` | Yes | Deploy succeeded. Now verify health endpoint as secondary check. |
| `live` | No | **Stale deploy.** The pushed commit wasn't picked up. Trigger manual deploy or investigate. |
| `build_failed` | — | Pull build logs: `render logs -r <ID> -o text --type build --limit 50`. Raise blocker with error. |
| `update_failed` | — | Service crashed on startup. Pull app logs: `render logs -r <ID> -o text --type app --limit 50`. Likely missing env var or import error. Raise blocker. |
| `build_in_progress` | — | Wait and re-check. Deploy still running. |

### After confirming deploy is live with correct commit:
```bash
# Secondary: verify health
curl -s https://<service-url>/health

# Tertiary: verify a real endpoint works (not just health)
curl -s https://<service-url>/api/<some-endpoint>
```

### Check ALL services, not just the one you changed:
A push triggers auto-deploy on ALL services (monorepo). Verify each service. A frontend build failure during a backend phase is a real problem — it means the next frontend push will also fail.

### If any service failed:
1. Pull build/app logs to diagnose
2. Raise a blocker with the full error output
3. **Do NOT proceed** — downstream work will be built against stale or broken infrastructure

---

## Debugging Playbooks

### "Site is down"
1. `render services list -o json` — check service status
2. `render deploys list -o json -r <ID>` — check if deploy failed
3. `render logs -r <ID> -o text --level error --limit 50` — find error

### "Deploy failed"
1. `render deploys list -o json -r <ID>` — find failed deploy ID
2. `render logs -r <ID> -o text --type build --limit 100` — build logs

### "App is slow"
1. `render logs -r <ID> -o text --limit 50` — check for obvious errors
2. Use API for metrics: `GET /v1/services/<ID>/metrics/http-latency`
3. Check instance count: `render services instances -o json -r <ID>`

---

## Detailed Reference (Supporting Files)

These files contain deep reference material — read them when you need specifics:

- [blueprint-reference.md](blueprint-reference.md) — Full render.yaml schema, all service fields, env var patterns, disks, scaling, preview environments, immutable fields
- [api-reference.md](api-reference.md) — All Render API endpoints organized by resource type
- [pricing-and-plans.md](pricing-and-plans.md) — Plan tiers, limits, free tier constraints, workspace tiers

$ARGUMENTS
