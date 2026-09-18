# Getting Started

You will end up with a working web app of your own: its code on GitHub, running on the internet, and Claude Code set up to build whatever you describe. Three steps.

1. **Get this folder onto your Mac.**
2. **Open Claude Code in it and type `/start`.**
3. **Answer Claude's questions.** It installs what's missing, walks you through the two accounts you need, and creates the project.

You do not need to know how to code. You do need a Mac, [Claude Code](https://claude.ai/code) installed and signed in, about 20 minutes, and a credit card for the hosting (about **$20 a month** per project while it exists; you can delete it any time).

---

## Step 1: Get Shipwright onto your Mac

Open **Terminal** (press ⌘-Space, type `Terminal`, press Enter). Paste this line and press Enter:

```bash
git clone https://github.com/nbdesai1992/shipwright.git ~/shipwright
```

If a window pops up offering to install "command line developer tools", click **Install**, wait for it to finish, then paste the line again. That is Apple's free toolkit; you only do this once.

## Step 2: Open Claude Code there and type /start

Paste this line and press Enter:

```bash
cd ~/shipwright && claude
```

Claude Code opens. Type:

```
/start
```

## Step 3: Follow along

Claude takes it from here, one step at a time. It will:

1. **Check your Mac** and install two small helper tools if they're missing. It may ask you to paste a line beginning with `!` — that runs a command for you and sometimes asks for your Mac password.
2. **Log you in to GitHub.** GitHub is where the code lives. If you don't have an account, create one at [github.com](https://github.com) (free) when Claude asks.
3. **Set up Render.** Render is where the app runs. Claude gives you the exact clicks, one at a time: create an account, add a card, allow Render to read your GitHub, create an "API key" and hand it to Claude. See the appendix below if you want to read ahead.
4. **Ask four questions:** what the project is called, what it does in one sentence, who it's for, and whether people will sign in.
5. **Ask before spending money**, then create everything. About five minutes. At the end it shows you two web addresses. That's your app, with a placeholder page.
6. **Tell you how to start building**, which is the next section.

## Then: build your app

Claude's last message tells you to open a **new** Terminal window and paste a line like:

```bash
cd ~/code/my-app && claude
```

That opens Claude Code inside your new project. Type `/spec create "` and describe what you want the app to do, then close the quote. Claude interviews you about it, writes a plan, and gives you a line beginning with `/goal`. Paste that line. Shipwright builds, tests, designs, and publishes on its own. Whenever it needs a decision from you, it asks a short question with options; answer in the chat. When it finishes, it gives you the live address.

Useful while it runs:

- `/status` shows where things stand.
- `/preflight` checks that everything is connected, and tells you the fix if not.
- Closing the window loses nothing. Reopen the project with the same `cd … && claude` line and type `/orchestrate` to continue.

---

## Where your keys live

All of these are private to your Mac and your project. None of them are ever put into GitHub.

| Key | Where it is stored | Used for |
|-----|--------------------|----------|
| Render API key | Your Mac's Claude settings file (`~/.claude/settings.json`), once, for every project | Letting Shipwright create and manage your servers |
| Clerk keys (only if sign-in) | The project's private settings file (`.claude/settings.local.json`) | Sign-in |
| Database password | The project's `backend/.env` | Testing against the real database |

If you ever need to replace the Render key: in Shipwright folder, paste `! python3 onboard.py --set-render-key` and enter the new one.

## Appendix: Render account setup, click by click

Claude walks you through this during `/start`; this is the same thing written down.

1. **Create an account** at [render.com](https://render.com). Sign up with GitHub or email. You land in the Dashboard with a workspace already created for you.
2. **Add a payment method.** Top-left, click your workspace name → **Billing** → **Add payment method**. Your app uses two small servers and a database, roughly $20 a month total. Deleting the project stops the charge.
3. **Connect GitHub.** Top-right, click your avatar → **Account Settings** → **GitHub** → **Connect**. GitHub asks which repositories Render may read; choose **All repositories** so every future project works without repeating this.
4. **Create an API key.** Top-right avatar → **Account Settings** → **API Keys** → **Create API Key**. Copy it. Back in Claude Code, paste `! python3 onboard.py --set-render-key` and enter the key when asked (typing is hidden). Claude confirms it was stored.

That is everything Render ever needs from you. You never create servers in the Dashboard; Shipwright does it.

## If something goes wrong

- During `/start`: Claude explains the error and how to fix it, then repeats the step. It is always safe to type `/start` again.
- Inside a project: type `/preflight`. Every line says PASS, WARN, or FAIL, and each FAIL comes with its fix.
- The three most common causes are: no card on Render, Render not allowed to read your GitHub, or a Render key that was deleted. Each takes a minute to fix in the Render Dashboard.

## Deleting a project

In the project folder, in Terminal:

```bash
python3 .claude/scripts/provision.py --destroy
```

It lists what will be deleted, asks you to type the project's name to confirm, and removes the servers and database. Render stops billing. Then delete the repository on GitHub: open it at github.com → **Settings** → scroll to the bottom → **Delete this repository**.

## Starting another project

Open Claude Code in Shipwright folder again (`cd ~/shipwright && claude`) and type `/start`. The account steps are already done, so it goes straight to the four questions.

---

Developers who want to choose the tech stack, keep a manual review step before each deploy, or run the wizard directly: see [SETUP.md](SETUP.md).
