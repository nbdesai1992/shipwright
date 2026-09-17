# Human Intervention Guide

When the software factory is running autonomously via `/goal` (or turn by turn via `/orchestrate`), there are specific moments where human intervention is required. This guide documents every known intervention point so you know what to expect.

## How Intervention Works

Workers raise **blockers** when they hit something they can't resolve. The runner records each one in the active brief under `## Blockers` — description, context, options, and an empty `Resolution:` line — and keeps working on everything that is not downstream of it. When nothing runnable remains, the brief moves to `briefs/3-blocked/` and the runner announces **NEEDS HUMAN INTERVENTION**.

You resolve a blocker the same way every time: open the brief, write your answer on its `Resolution:` line, then run `/orchestrate`. The runner moves the brief back to `2-active/`, records your decision in the Progress Log, and re-plans the blocked subtasks. There is no chat-style "reply to the orchestrator" — the brief file is the channel.

You can check for blockers at any time with `/status blockers`.

---

## Intervention Categories

### 1. Deployment Platform Authentication

**When:** First time the infra-worker tries to use the deployment CLI or API.

**Symptom:** Blocker with type `external-action`, message about authentication failure or missing credentials.

**What to do:** Run `! render login` in the Claude Code prompt (the `!` prefix runs it interactively). This opens a browser for OAuth. After login, the CLI stores a token at `~/.render/cli.yaml`; the deploy skill reads the API key from that file for direct API calls, so there is no separate key to set. Then write "logged in" on the blocker's `Resolution:` line and run `/orchestrate`.

Tokens expire. If `render workspace current -o json` prints `401 Unauthorized`, the fix is the same `render login`.

**Prevention:** Log in before the first run and confirm `render workspace current -o json` prints your workspace.

#### Render Setup (do this once before your first run with deployment tasks)

1. **Install:** `brew install render`
2. **Authenticate:** `render login` — opens a browser for OAuth
3. **Verify:** `render workspace current -o json` should show your workspace name and `tea-...` ID
4. **Select workspace** (if you have multiple): `render workspace set <id>` — this must match the pin in `.claude/render-workspace`, or every Render command in the project is blocked by the workspace guard hook
5. **Credentials stored at:** `~/.render/cli.yaml`

---

### 2. Database Provisioning

**When:** The infra-worker's first task audits Render and finds the services or database declared in `render.yaml` do not exist.

**Symptom:** Blocker of type `external-action` asking you to create the Blueprint Instance.

**What to do:** Render Dashboard → **Blueprints → New Blueprint Instance → select your repo**. Render reads `render.yaml` and creates the API service, frontend service, and Postgres database (a paid `basic-256mb` plan — it persists, unlike the free tier's 30-day expiry). The infra-worker never creates services or databases itself; it only verifies and uses what the blueprint created. Once the services show up, write "created" on the `Resolution:` line and run `/orchestrate`.

**Prevention:** Create the Blueprint Instance right after onboarding pushes the repo — SETUP.md Step 2c.

---

### 3. Authentication Keys (Clerk)

**When:** The backend or frontend worker needs Clerk keys to set up auth, and they're not yet configured in Render.

**Symptom:** Blocker with type `external-action`, message about missing `CLERK_SECRET_KEY` or `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`. Or the infra-worker's state audit flags them as empty (declared as `sync: false` but no value set).

**What to do:**
1. Go to [clerk.com](https://clerk.com) → your application (or create one)
2. Copy the Publishable Key and Secret Key
3. In Render Dashboard, set on the appropriate services:
   - Frontend: `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`, `CLERK_SECRET_KEY`
   - Backend: `CLERK_SECRET_KEY`
4. Write "keys set" on the blocker's `Resolution:` line and run `/orchestrate`

**Prevention:** Create your Clerk app and set the keys in Render BEFORE the first run. See SETUP.md Step 2b.

---

### 4. Environment Variables and Secrets

**When:** A worker needs an API key, secret, or connection string that doesn't exist yet.

**Symptom:** Blocker with type `needs-human-decision` or `external-action`, listing the env vars needed.

**What to do:**
- Create the required accounts (Stripe, SendGrid, etc.)
- Provide the keys/secrets when asked
- The worker will tell you exactly where to set them (platform env vars, `.env` file, etc.)

**Prevention:** If your spec involves third-party services, set up those accounts and have API keys ready before orchestrating.

---

### 5. Git and Repository Setup

**When:** The infra-worker needs to connect a deployment service to your git repo.

**Symptom:** Blocker about missing git remote, or deployment service can't find the repo.

**What to do:**
- Create the GitHub/GitLab repo if it doesn't exist
- Push your code to it
- Ensure the deployment platform has access (GitHub app installed, OAuth connected, etc.)

**Prevention:** Have your git repo set up and pushed before running infrastructure tasks.

---

### 6. Push to Deploy (Code Review Checkpoint)

**When:** After backend or frontend code is written, the infra-worker commits the code and needs you to push it to trigger Render's auto-deploy.

**Symptom:** Blocker with type `external-action`, message like "Code committed. Please run `git push origin main` to deploy."

**What to do:**
1. Review the changes if desired: `git log --oneline -5` and `git diff HEAD~1`
2. Push: `git push origin main`
3. Render auto-deploys both services on commit
4. Write "pushed" on the blocker's `Resolution:` line and run `/orchestrate` — the infra-worker then verifies the deploy went live with the right commit SHA

**This is intentional.** Pushing requires authentication and is a natural checkpoint for you to review what was built before it goes live. The orchestrator will not push on its own.

**Frequency:** Typically twice per orchestration — once after backend is complete, once after frontend is complete.

---

### 7. DNS and Custom Domains

**When:** A deployment task includes setting up a custom domain.

**Symptom:** Blocker about DNS verification failure.

**What to do:**
- Go to your domain registrar
- Add the DNS records specified in the blocker (usually a CNAME or A record)
- Wait for propagation (can take minutes to hours)
- Write "records added" on the `Resolution:` line and run `/orchestrate`

**Prevention:** DNS is inherently manual and asynchronous. Plan for this to take time.

---

### 8. Unclear Requirements

**When:** A worker encounters ambiguity in the spec that prevents implementation.

**Symptom:** Blocker with type `unclear-requirement`, describing what's ambiguous.

**What to do:**
- Read the blocker in the brief carefully — it describes the ambiguity and lists options
- Write your decision on the blocker's `Resolution:` line, then run `/orchestrate`
- The runner records your decision in the brief's Progress Log for future reference

**Example:** "The spec says 'users can share content' but doesn't specify: (1) share via link, (2) share to specific users, or (3) both. Which approach?"

---

### 9. Architecture Decisions

**When:** A worker faces a significant technical choice that could go multiple ways.

**Symptom:** Blocker with type `needs-human-decision`, presenting options with trade-offs.

**What to do:**
- Review the options presented
- Consider the trade-offs (the worker usually lists pros/cons)
- Make a decision

**Example:** "Should the API use REST or GraphQL? REST is simpler and matches the current codebase. GraphQL would reduce over-fetching for the dashboard but adds complexity."

---

### 10. Worker Failures (Max Attempts Reached)

**When:** A worker has failed 3 times on the same task.

**Symptom:** The orchestrator surfaces the task as a blocker after max attempts, showing error details from each attempt.

**What to do:**
- Read the error details from the task's progress log
- Common causes:
  - **Test failures that need design change:** The acceptance criteria may be too strict or contradictory
  - **Missing dependency:** Something the worker needs doesn't exist yet
  - **Environment issue:** Missing package, wrong Node/Python version, etc.
- Either fix the root cause yourself and write what you did on the `Resolution:` line, or adjust the spec with `/spec update`. Then run `/orchestrate` — the attempt counter resets for the re-planned subtask

---

### 11. Design Direction Approval

**When:** A frontend worker runs the bold-design pre-design exploration for the first time.

**Symptom:** Not a blocker — the worker writes `session/design-direction.md` and proceeds. But you may want to review it.

**What to do:**
- After the first frontend task completes, review `session/design-direction.md`
- If the design direction is wrong, use `/spec update` to add design constraints, then the orchestrator will re-plan

**This is optional.** The worker will proceed without your input. But early review prevents wasted iterations.

---

## Minimizing Interventions

To get the smoothest autonomous run:

1. **Before the first run:**
   - Log in to the Render CLI and confirm the workspace
   - Have your git repo set up and pushed
   - Have API keys ready for any third-party services in the spec
   - Create the Blueprint Instance so the services and database exist

### Render Pre-Flight Checklist

Do this **once** before your first run:

- [ ] `render` CLI installed and `render workspace current -o json` prints your workspace (no `401`)
- [ ] The workspace it prints matches `.claude/render-workspace` in the project (the guard hook blocks every Render command otherwise)
- [ ] `dev-browser` installed (`npm install -g dev-browser`) if the project has a frontend
- [ ] `render.yaml` exists in repo root (generated during onboarding)
- [ ] Git repo created, committed, and pushed to GitHub
- [ ] Env group (`general_builder_keys` by default) exists in the workspace
- [ ] **Blueprint Instance created**: Render Dashboard → Blueprints → "New Blueprint Instance" → select your repo
  - Render reads `render.yaml` and creates all services + database
  - The skeleton apps deploy on the first build; both `/health` endpoints should return `{"status": "ok"}`
- [ ] `sync: false` env vars (Clerk keys) set in the Render Dashboard

After this setup, deploys happen through your `git push` — Render auto-deploys on commit, and the infra-worker verifies each deploy went live. The factory never creates services and never pushes on its own.

2. **Write detailed specs:**
   - The more specific your acceptance criteria, the fewer `unclear-requirement` blockers
   - Explicitly state technology preferences in Technical Constraints
   - Put things in Out of Scope to prevent workers from over-engineering

3. **Stay available:**
   - Blockers are parked, not fatal — the runner keeps working on everything else, then routes the brief to `3-blocked/` when nothing runnable remains
   - Check `/status blockers` periodically
   - Quick answers on the `Resolution:` lines keep the pipeline moving

---

## Intervention Quick Reference

| Intervention | Type | Typical Resolution Time | Can Prevent? |
|-------------|------|------------------------|-------------|
| Platform auth | external-action | 2 minutes | Yes — login beforehand |
| Database provisioning | external-action | 5 minutes | Yes — Blueprint Instance beforehand |
| **Clerk auth keys** | **external-action** | **5 minutes** | **Yes — create Clerk app beforehand** |
| Env vars / secrets | needs-human-decision | 5-30 minutes | Partially — have keys ready |
| Git repo setup | external-action | 5 minutes | Yes — set up beforehand |
| **Push to deploy** | **external-action** | **1-2 minutes** | **No — intentional checkpoint** |
| DNS / domains | external-action | Minutes to hours | No — inherently async |
| Unclear requirements | unclear-requirement | 1-5 minutes | Yes — write detailed specs |
| Architecture decisions | needs-human-decision | 2-10 minutes | Partially — constrain in spec |
| Worker failures | max-attempts | 5-30 minutes | No — but rare |
| Design review | (optional) | 5 minutes | N/A — optional |
