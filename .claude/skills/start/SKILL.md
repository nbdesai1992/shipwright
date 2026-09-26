---
name: start
description: Create a new project with Consul, end to end. Use when someone opens Claude Code in the consul repo and wants to start a new app — it checks their machine, walks them through GitHub and Render account setup one step at a time, asks four plain questions, runs the wizard, and leaves them with a new repo on GitHub whose services are live on Render.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep
argument-hint: "[nothing — just /start]"
---

# /start — from this repo to a live project

You are guiding a person who may never have used a terminal beyond opening Claude Code. Your job is to get them from here to a new project repo with live Render services, asking for one thing at a time and explaining each thing in plain words. The deterministic engine is `onboard.py` in this repo; you drive it with flags so they never see its prompts.

## Ground rules

- **One step at a time.** Ask for a single thing, wait for it, confirm you got it, move on. Never list five prerequisites up front.
- **Plain language.** "Your code will live on GitHub" not "we need a remote". Expand any technical word the first time it appears. No file paths unless they must type one.
- **Exact instructions.** When they must do something in a browser, give the click path exactly as the page shows it. When they must type something, give the whole line to paste.
- **Secrets stay out of files you write.** Keys go through the scripts, which store them in gitignored places. If they paste a key in chat, use it immediately via a flag and tell them where it was stored. Never echo a key back.
- **Money is announced before it is spent.** Say the Render cost (about $20/month per project while it exists; deleting the project stops it) before anything is created, and get an explicit yes.
- **Nothing here is fatal.** If a step fails, read the error, say what it means in one sentence, give the fix, and repeat the step. Everything is safe to re-run.

## Step 0 — set expectations (one short message)

Tell them: this creates a new web app project for them — code on GitHub, running on Render, with Claude Code set up inside it to build features they describe. It takes about 15 minutes the first time, mostly account setup, and they'll need to sign up for GitHub and Render if they haven't. Ask them to say "ready" when they are.

## Step 1 — check the machine

Run:
```bash
python3 onboard.py --check
```
Read the `[MISSING]` lines. Fix each in this order, one message per fix, waiting between them:

- **git / python3 missing** → "Your Mac needs Apple's free developer tools. Paste this and accept the popup: `! xcode-select --install`. Tell me when it finishes." Re-run the check.
- **gh (GitHub's command-line tool) missing** → if `brew --version` works: run `brew install gh` yourself. Otherwise download the latest macOS `.pkg` from GitHub's releases (query `https://api.github.com/repos/cli/cli/releases/latest` for the `macOS_universal.pkg` asset URL, `curl -L` it to `/tmp/gh.pkg`) and ask them to run `! sudo installer -pkg /tmp/gh.pkg -target /` (it asks for their Mac password). Re-run the check.
- **node missing or older than 18** → install the official prebuilt Node LTS into their home folder yourself; no password, no Homebrew (Homebrew builds Node from source on older macOS and can take hours):
  ```bash
  mkdir -p ~/.local && cd ~/.local && A=$([ "$(uname -m)" = arm64 ] && echo arm64 || echo x64) && \
  V=$(curl -fsSL https://nodejs.org/dist/index.json | python3 -c "import json,sys;print([r['version'] for r in json.load(sys.stdin) if r.get('lts')][0])") && \
  curl -fsSL -o node.tgz "https://nodejs.org/dist/$V/node-$V-darwin-$A.tar.gz" && rm -rf node && tar xzf node.tgz && mv node-$V-darwin-$A node && rm node.tgz
  ```
  Then make it permanent: append `export PATH="$HOME/.local/node/bin:$PATH"` to `~/.zshrc` (create the file if missing) and use that PATH for every command you run afterwards. Node is only needed so Claude can preview the app's screens on their machine.
- **dev-browser missing** → `PATH="$HOME/.local/node/bin:$PATH" npm install -g dev-browser`, then verify with `printf 'console.log(1)\n' | dev-browser --headless`. If it cannot find Chrome, run `dev-browser install`.
- **render CLI** is marked optional. Never install it; Consul talks to Render directly.

## Step 2 — GitHub

Run `gh auth status`. If it fails:

> "Your code will live in a private repository on GitHub, so I need you logged in there. If you don't have an account, create one at github.com first (free). Then paste this and follow the prompts:
> `! gh auth login`
> Choose **GitHub.com**, then **HTTPS**, answer **Yes** to authenticating git, then **Login with a web browser**. It shows a code; press Enter, paste the code in the browser, approve. Tell me when it says you're logged in."

Re-run `gh auth status` to confirm. Don't move on until it passes.

## Step 3 — Render

Run `python3 onboard.py --check` again and look for the Render credential line. If it says a key is present, skip to Step 4. Otherwise walk them through, **one message per bullet, waiting for each**:

1. **Account:** "Render is where your app will run. Sign up at render.com (free to sign up). Tell me when you're in the Dashboard."
2. **Payment:** "Your app needs two small servers and a database, about $20 a month while the project exists. Render needs a card for that. In the Dashboard: top-left workspace name → **Billing** → add a payment method. Tell me when done."
3. **Connect GitHub:** "Render has to be allowed to read your code from GitHub. Top-right avatar → **Account Settings** → **GitHub** → **Connect** (or Configure). When GitHub asks which repositories, choose **All repositories** — that way each new project works without coming back here. Tell me when done."
4. **API key:** "Last one. This lets me manage your Render services for you, so you never click around the Dashboard again. Top-right avatar → **Account Settings** → **API Keys** → **Create API Key**. Copy it, then paste this line and paste the key when asked (it's hidden as you type):
   `! python3 onboard.py --set-render-key`
   Or paste the key here and I'll store it."
   If they paste it in chat: run `python3 onboard.py --set-render-key --render-api-key <key>` immediately, then say: "Stored on this Mac in a private Claude settings file. It works for every project you create here and I won't repeat it." If the script says Render rejected it, ask them to check they copied the whole key.

## Step 4 — the four questions

Ask conversationally, one or two at a time:

1. What should the project be called? (Anything; "Invoice Tracker".)
2. In one sentence, what does it do?
3. Who is it for, or what world does it live in? (This shapes how it looks: "freelancers sending invoices", "a wedding planner".)
4. Will people need to sign in with their own account? If **yes**: "Sign-in is handled by a free service called Clerk. Go to clerk.com, sign up, **Create Application**, name it after the project, and open its **API Keys** page. Paste the **Publishable key** (starts with pk_) and the **Secret key** (starts with sk_) here." If they'd rather add sign-in later, say fine — the app just won't have accounts until then.

Derive the folder name: lowercase, dashes for spaces (`invoice-tracker`). Default location `~/code/<slug>`; tell them where it will go and let them change it.

## Step 5 — create it

Before running, one message:

> "Here's what happens next: I create a private GitHub repository called **<slug>**, put the starter code in it, and create the database and two servers on Render. Render billing starts now — about $20/month until you delete the project. Takes about 5 minutes. Go ahead?"

On an explicit yes, run (fill every value; quote them):
```bash
python3 onboard.py ~/code/<slug> --quick --yes \
  --name "<name>" --description "<sentence>" --domain "<who/world>" --login <yes|no> \
  [--clerk-publishable-key "<pk>" --clerk-secret-key "<sk>"]
```
Relay progress in plain words as it runs ("repository created", "database is being set up — this is the slow part", "servers created"). The wizard prints two web addresses at the end; those are their app, showing a placeholder page for now.

If provisioning fails, the output has a `[FAIL]` line with a `→ fix`. Say what it means (the three real causes: no card on Render, Render can't see the repository because GitHub wasn't connected, or a bad key), have them fix it, then run:
```bash
cd ~/code/<slug> && python3 .claude/scripts/provision.py --yes
```

## Step 6 — hand off

Final message, exactly this shape:

> "Done. Your project is at **~/code/<slug>**, on GitHub as **<slug>**, and live at:
> - <frontend url> (what people will see)
> - <backend url> (the engine behind it)
>
> To start building, open a **new** Terminal window and paste:
> `cd ~/code/<slug> && claude`
>
> Then type `/spec create "` followed by what you want the app to do, and close the quote. Claude will interview you, write a plan, and hand you a line starting with `/goal` — paste it and Consul builds. If it ever asks you a question, just answer in the chat.
>
> Where your keys live (all private, none of them go to GitHub): Render key in your Mac's Claude settings; Clerk keys and the database password inside the project's private settings files.
>
> To delete the project later: in the project folder, `python3 .claude/scripts/provision.py --destroy`, then delete the repository on GitHub."

## If they run /start again

It is safe. The machine check and GitHub/Render checks pass instantly when already done; go straight to the four questions for the next project.

$ARGUMENTS
