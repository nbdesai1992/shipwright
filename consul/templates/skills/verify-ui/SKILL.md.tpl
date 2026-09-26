---
name: verify-ui
description: Autonomous UI verification loop. Use proactively when making frontend/UI changes to visually verify they look correct. Screenshots the running app with dev-browser, analyzes the result, and iterates until the UI meets requirements.
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
argument-hint: "[description of what to verify or fix in the UI]"
---

# UI Verification Loop

You are an autonomous UI verification agent. Your job is to iterate on UI code changes by visually inspecting the running app with dev-browser screenshots.

## Mode: Local or Deployed

Check `$ARGUMENTS` for a URL. This determines your mode:

- **If a deployed URL is provided** (e.g., `https://...onrender.com`): Screenshot that URL directly. Do NOT start a local dev server. You are verifying the deployed site. You can still make code changes, but they require a re-deploy to take effect — raise a blocker if changes are needed.
- **If no URL is provided** (default): Use the local dev server for fast iteration. This is the mode described below.

## Setup (Local Mode)

**Note:** The port and command below were set during onboarding. If they've changed, check CLAUDE.md for current values.

1. **Start the dev server** (if not already running):
   ```bash
   cd frontend && {{DEV_SERVER_COMMAND}} &
   ```
   Wait 2 seconds, then verify it's running:
   ```bash
   curl -s http://localhost:{{DEV_SERVER_PORT}}/
   ```

2. **If the server is already running** on port {{DEV_SERVER_PORT}}, skip startup.

## The Loop

Repeat the following cycle. You MUST complete at least one full cycle. Stop when requirements are met or after 5 iterations (whichever comes first).

### Step 1: Screenshot the current state

Take a full-page screenshot. Use the deployed URL if in deployed mode, otherwise localhost:
```bash
dev-browser --headless <<'SCRIPT'
const page = await browser.getPage("{{PROJECT_SLUG}}");
await page.setViewportSize({ width: 1440, height: 900 });
await page.goto("{TARGET_URL}", { waitUntil: "networkidle" });
await page.waitForTimeout(1000);
const buf = await page.screenshot({ fullPage: true });
const path = await saveScreenshot(buf, "current-state");
console.log("Screenshot saved to: " + path);
SCRIPT
```

Replace `{TARGET_URL}` with the deployed URL from `$ARGUMENTS`, or `http://localhost:{{DEV_SERVER_PORT}}` for local mode.

Then **read the screenshot image** using the Read tool to visually inspect it.

### Step 2: Analyze

Compare what you see against:
1. The user's requirements (`$ARGUMENTS`)
2. If `session/design-direction.md` exists, evaluate against the design direction
3. If bold-design quality gates apply, run them:
   - **AI Slop Test**: Would someone immediately say "AI made this"? If yes, it fails.
   - **Swap Test**: Could you swap the typeface/layout without anyone noticing? If yes, too generic.
   - **Squint Test**: Is hierarchy visible when blurred?

List:
- What looks correct
- What needs to change
- Specific elements that are broken, misaligned, or missing

### Step 3: Make code changes

Edit the relevant frontend files to fix the issues found.

### Step 4: Reload and re-screenshot

```bash
dev-browser --headless <<'SCRIPT'
const page = await browser.getPage("{{PROJECT_SLUG}}");
await page.reload({ waitUntil: "networkidle" });
await page.waitForTimeout(1000);
const buf = await page.screenshot({ fullPage: true });
const path = await saveScreenshot(buf, "iteration-N");
console.log("Screenshot saved to: " + path);
SCRIPT
```

Replace `iteration-N` with the actual iteration number (e.g., `iteration-1`, `iteration-2`).

Read the new screenshot and evaluate progress.

### Step 5: Decide

- **Requirements met?** Report what was done and stop.
- **Not yet?** Go back to Step 3. State what still needs fixing.
- **5 iterations reached?** Stop, report current state and remaining issues.

## Important Rules

- You MUST read each screenshot image after saving it. The screenshot is useless if you don't look at it.
- Keep named page `"{{PROJECT_SLUG}}"` consistent across all dev-browser calls so state persists.
- If the server crashes or port {{DEV_SERVER_PORT}} is busy, kill the old process first: `lsof -ti:{{DEV_SERVER_PORT}} | xargs kill -9 2>/dev/null`
- After you are done, kill the dev server: `lsof -ti:{{DEV_SERVER_PORT}} | xargs kill -9 2>/dev/null`
- In local mode: do NOT push or deploy. The user will deploy separately.
- In deployed mode: do NOT make code changes without raising a blocker (changes need a re-deploy cycle).
- If you are in an orchestrated workflow (session/ directory exists), follow worker protocol for progress reporting.

## Responsive Testing (Optional)

If the user asks for responsive testing, also screenshot at mobile size:
```bash
dev-browser --headless <<'SCRIPT'
const page = await browser.getPage("{{PROJECT_SLUG}}-mobile");
await page.setViewportSize({ width: 390, height: 844 });
await page.goto("http://localhost:{{DEV_SERVER_PORT}}", { waitUntil: "networkidle" });
await page.waitForTimeout(1000);
const buf = await page.screenshot({ fullPage: true });
const path = await saveScreenshot(buf, "mobile-state");
console.log("Screenshot saved to: " + path);
SCRIPT
```

$ARGUMENTS
