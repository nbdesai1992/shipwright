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

**What to do:** Either run `! render login` in the Claude Code prompt (the `!` prefix runs it interactively; opens a browser, stores a token that expires), or — the durable fix — create a long-lived API key (Render Dashboard → Account Settings → API Keys) and put it in the `env` block of `.claude/settings.local.json` as `RENDER_API_KEY`. Then write "credential set" on the blocker's `Resolution:` line and run `/orchestrate`.

Every Render call in the factory goes through `.claude/scripts/render-api-key.sh`, which prefers the long-lived key and falls back to the login token; `--source` tells you which one is in use and whether the token has expired.

**Prevention:** Run `/preflight` before the first run. It reports the credential source, whether it has expired, and whether it can see the pinned workspace.

#### Render Setup (do this once before your first run with deployment tasks)

1. **Install:** `brew install render`
2. **Authenticate:** `render login` — opens a browser for OAuth
3. **Verify:** `render workspace current -o json` should show your workspace name and `tea-...` ID
4. **Select workspace** (if you have multiple): `render workspace set <id>` — this must match the pin in `.claude/render-workspace`, or every Render command in the project is blocked by the workspace guard hook
5. **Credentials stored at:** `~/.render/cli.yaml`

---

### 2. Database Provisioning

**When:** The infra-worker's first task runs `provision.py` and it fails.

**Symptom:** Blocker of type `external-action` carrying the provisioner's `[FAIL]` line and its `→ fix`.

**What to do:** The fix text names one of three account-level causes: no payment method on the Render workspace (Dashboard → Billing), Render cannot read the repo (Dashboard → Account Settings → GitHub → grant access), or an expired credential (`render login` or a new API key). Do that, then re-run `python3 .claude/scripts/provision.py` yourself or write "fixed" on the `Resolution:` line and run `/orchestrate` — the infra-worker re-runs it. Nobody creates services by hand; the provisioner is the only path, and it is idempotent.

**Prevention:** The wizard runs the provisioner at onboarding. If it succeeded then, this blocker does not occur.

---

### 3. Authentication Keys (Clerk)

**When:** The backend or frontend worker needs Clerk keys to set up auth, and they're not yet configured in Render.

**Symptom:** Blocker with type `external-action`, message about missing `CLERK_SECRET_KEY` or `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`. Or the infra-worker's state audit flags them as empty (declared as `sync: false` but no value set).

**What to do:**
1. Go to [clerk.com](https://clerk.com) → your application (or create one) → API Keys
2. Run, in the project directory:
   ```bash
   python3 .claude/scripts/provision.py --set NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_... --set CLERK_SECRET_KEY=sk_...
   ```
   It sets each key on every service whose `render.yaml` entry declares it.
3. Write "keys set" on the blocker's `Resolution:` line and run `/orchestrate`

**Prevention:** Paste the Clerk keys when the wizard asks; the provisioner sets them during onboarding.

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

**When:** After backend or frontend code is written, the infra-worker commits the code and the project's **push policy** (CLAUDE.md → Deployment) is `human`. Under `factory` (the Quick Start default) the runner pushes itself and this intervention never occurs.

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

Run `/preflight` (or `python3 .claude/scripts/preflight.py`). It checks all of this and prints a fix under every failure:

- [ ] `render` CLI installed; a Render credential that works (long-lived `RENDER_API_KEY`, or a `render login` token that has not expired)
- [ ] The credential can see the workspace pinned in `.claude/render-workspace`, and the CLI's current workspace matches it (the guard hook blocks every Render command otherwise)
- [ ] `dev-browser` installed (`npm install -g dev-browser`) if the project has a frontend
- [ ] `render.yaml` exists in repo root (generated during onboarding)
- [ ] Git repo created, committed, and pushed to GitHub
- [ ] Every service, database and env group in `render.yaml` exists on Render — `python3 .claude/scripts/provision.py` creates whatever is missing (the wizard ran it at onboarding)
  - The skeleton apps deploy on the first build; both `/health` endpoints should return `{"status": "ok"}`
- [ ] `sync: false` secrets (Clerk keys) have values — `provision.py --set KEY=VALUE`

The runner also runs preflight the first time it pulls a brief from the backlog and parks any failure as a blocker with the same fix text. After this setup, deploys happen through your `git push` — Render auto-deploys on commit, and the infra-worker verifies each deploy went live. The factory never creates services and never pushes on its own.

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
| Provisioning failed (billing / GitHub access) | external-action | 5 minutes | Yes — account setup beforehand |
| **Clerk auth keys** | **external-action** | **5 minutes** | **Yes — create Clerk app beforehand** |
| Env vars / secrets | needs-human-decision | 5-30 minutes | Partially — have keys ready |
| Git repo setup | external-action | 5 minutes | Yes — set up beforehand |
| **Push to deploy** | **external-action** | **1-2 minutes** | **No — intentional checkpoint** |
| DNS / domains | external-action | Minutes to hours | No — inherently async |
| Unclear requirements | unclear-requirement | 1-5 minutes | Yes — write detailed specs |
| Architecture decisions | needs-human-decision | 2-10 minutes | Partially — constrain in spec |
| Worker failures | max-attempts | 5-30 minutes | No — but rare |
| Design review | (optional) | 5 minutes | N/A — optional |
