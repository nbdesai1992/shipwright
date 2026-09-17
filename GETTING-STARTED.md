# Getting Started

From nothing to a live web app in three steps:

1. **Clone this repo.**
2. **Run the wizard.** It asks four questions.
3. **A new project repo is created** — on your computer, on GitHub, and running on Render — with Claude Code set up inside it to build whatever you describe.

This guide is for macOS and assumes you can open the Terminal app and paste commands. You do not need to know how to code.

---

## Before you start: three accounts

You will create accounts on three websites. Each takes a few minutes. Have them done before you open the Terminal.

### 1. GitHub — where the code lives
- Sign up at [github.com](https://github.com). Free.

### 2. Render — where the app runs
- Sign up at [render.com](https://render.com).
- **Add a payment method:** Dashboard → your workspace name (top left) → **Billing**. The factory creates two small web services and one database. Expect roughly **$20 a month** while the project exists. You can delete everything from the Dashboard at any time.
- **Connect GitHub to Render:** Dashboard → your avatar (top right) → **Account Settings → GitHub → Connect**. Grant access to all repositories, or come back after step 2 below and grant access to the new one. Render cannot read your code without this.
- **Create an API key:** Dashboard → your avatar (top right) → **Account Settings → API Keys → Create API Key**. Copy it; the bootstrap asks for it once and remembers it for every project on your computer. This is the only credential the factory needs — there is no separate login step.

### 3. Clerk — only if people will sign in to your app
- Sign up at [clerk.com](https://clerk.com). Free to start.
- **Create Application**, name it after your project, then open **API Keys** and keep the page open. The wizard asks for the two keys shown there.
- If your app has no user accounts, skip Clerk entirely.

---

## Step 1: Clone this repo and run the bootstrap

Open **Terminal** (press ⌘-Space, type `Terminal`, press Enter). Paste these lines one at a time:

```bash
git clone https://github.com/nbdesai1992/software-factory.git ~/software-factory
~/software-factory/bootstrap.sh ~/code/my-app
```

Replace `my-app` with a short name for your project (lowercase, dashes instead of spaces). The bootstrap installs the tools the factory needs and logs you in:

- If it says Homebrew is missing, install it from [brew.sh](https://brew.sh) (one paste), then run the bootstrap again.
- When your browser opens asking you to log in to **GitHub**, approve it and return to the Terminal.
- When it asks for your **Render API key**, paste the key you created (typing is hidden). It is stored once, machine-wide.

It then starts the wizard automatically.

## Step 2: Answer the wizard

Press Enter to accept the first question's default (Quick Start). Then:

| Question | Example answer |
|----------|----------------|
| What is the project called? | `Invoice Tracker` |
| In one sentence, what does it do? | `Lets freelancers send invoices and see who has paid.` |
| Who is it for, or what world does it live in? | `freelancers sending invoices` |
| Will people need to sign in with an account? | `y` if your app has user accounts, otherwise `n` |
| Clerk keys (only if you said y) | paste the two keys from Clerk. Typing is hidden. |

Then say **yes** to each of: create the GitHub repo, commit, push, and create the Render services. The last one takes a couple of minutes while Render sets up the database. When it finishes you will see two web addresses ending in `onrender.com`. Those are your app. Right now they show a placeholder page.

## Step 3: Check, then build

Still in Terminal:

```bash
cd ~/code/my-app
python3 .claude/scripts/preflight.py
```

Every line should say `PASS` or `WARN`. A `FAIL` line comes with a fix underneath; do the fix and run it again. Then:

```bash
claude
```

Claude Code opens inside your project. Type:

```
/spec create "describe what you want the app to do"
```

Claude interviews you about the product, in plain language, then writes a plan called a **brief** and hands you a line starting with `/goal`. Paste that line. The factory now works on its own: it builds the app, tests it, designs the screens, and puts each piece live on Render. It stops only when it needs a decision from you, and it asks that as a short question with options. Answer in the chat.

When it finishes, it gives you the live address and tells you what you can do there.

---

## While it runs

- `/status` shows where things stand.
- If the run ends with **NEEDS HUMAN INTERVENTION**, read the questions it lists, answer them in the chat, and type `/orchestrate` to continue.
- Every change is saved to your GitHub repo, so nothing is lost if you close the Terminal. Open it again, run `claude`, and type `/orchestrate` to pick up where it left off.
- A full build uses a meaningful amount of Claude usage. Long runs are normal.

## If something goes wrong

Run the readiness check first; it names the cause and the fix:

```bash
python3 .claude/scripts/preflight.py
```

The three most common causes:

| What you see | What it means | Fix |
|--------------|---------------|-----|
| `Render rejected the key (401)` | The API key was deleted or is wrong | Create a new one in the Render Dashboard and run `python3 ~/software-factory/onboard.py --set-render-key` |
| `could not create service … repo` | Render cannot see your GitHub repo | Render Dashboard → Account Settings → GitHub → grant access to the repo, then `python3 .claude/scripts/provision.py` |
| `402` or `403` when creating a database or service | No payment method on the Render workspace | Render Dashboard → Billing, then `python3 .claude/scripts/provision.py` |

## Starting another project

Run the bootstrap again with a new folder name. Each project is its own repo and its own set of Render services.

```bash
~/software-factory/bootstrap.sh ~/code/another-app
```

Developers who want to choose the tech stack, keep a manual review step before each deploy, or add a platform: see [SETUP.md](SETUP.md) and answer `y` to the wizard's first question.
