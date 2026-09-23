# agent-kit

The setup that makes Claude Code sessions continuous: a local memory server, the
hooks that use it without being asked, and the file scaffolding an agent reads
at the start of every session.

Everything runs on your own machine. Nothing in here connects to anyone else's
network, and nothing leaves the box.

---

## If you are an agent reading this

You have been asked to set this up. Work through **Setup** below in order. After
each step, run its check and confirm it passed before moving on. The script is
safe to re-run; if a step fails, fix the cause and run it again rather than
skipping ahead.

Four things need your human, listed under **What needs a person**. Ask for
those rather than guessing. Everything else you can do unattended.

When you are done, report: the health check output, the hook status, and which
of the optional decisions are still outstanding.

---

## What you get

| Piece | What it does |
|---|---|
| **Nellie** | A local server that indexes your code and stores lessons and checkpoints. Semantic search over everything you have worked on. |
| **Hooks** | Nellie installs Claude Code hooks that load context at session start, save at session end, and add relevant memory to each turn. This is the part that makes sessions feel continuous rather than starting from zero. |
| **`templates/`** | `CLAUDE.md`, `purpose.md` and a `memory/` folder. Plain files, in your repo, that tell an agent what the project is and what has been learned. |
| **[remember](https://github.com/mmorris35/remember)** | A `~/wiki/` of plain markdown about *you*: who you are, how you work, your people. Every session in every folder reads it first. Karpathy's LLM-wiki pattern, zero install. |
| **`telegram/`** (optional) | Runs an agent as a service you message on Telegram. See **Optional: talk to it on Telegram**. |

Three layers, three jobs:

| Layer | Knows | Lives in |
|---|---|---|
| **remember** | **you**: identity, style, preferences, people | `~/wiki/`, loaded in every session |
| **`memory/`** | **this project**: decisions and reasons, mistakes, open questions | the repo, diffs like code |
| **Nellie** | **everything, searchable**: code, lessons, checkpoints across projects | a local server, injected by hooks |

remember is **personal**, the files are **deep**, Nellie is **wide**.

## Requirements

- Linux with systemd, and `sudo` for installing packages.
- [Claude Code](https://docs.claude.com/en/docs/claude-code) already installed
  and signed in. Check: `claude --version`.
- About 3 GB of disk and 20–40 minutes, most of it a Rust build on first run.
- Network access to github.com and crates.io.

### Which machine

If there is a choice, pick the box where you already run Claude Code, and
where your repositories already are. Nellie indexes what it can see, and the
hooks only help the sessions that run beside them. A VM is fine. What matters:

- Linux with systemd, 2+ cores, 4 GB RAM, ~3 GB free disk.
- It stays up. A server you shut down each night is a memory that forgets.
- **Its disk is backed up, or `~/.local/share/nellie` is.** See below.

## Setup

### 1. See what is missing

```bash
./setup.sh --check
```

Changes nothing. It reports which prerequisites are absent and whether anything
is already running. **Check:** it prints a port, a watch directory, and a list
of anything missing.

### 2. Run it

```bash
./setup.sh
```

Idempotent, and every step checks before acting. It will:

1. install build dependencies with `apt` (sudo prompts here);
2. install Rust if `cargo` is absent;
3. clone and build [Nellie](https://github.com/mmorris35/nellie) into `~/src/nellie`;
4. download the embedding model, one time;
5. install a **systemd user service** bound to `127.0.0.1:8765`;
6. register Nellie as an MCP server for Claude Code;
7. install the Nellie hooks;
8. verify all of it.

Useful flags: `--port N`, `--watch DIR` (what Nellie indexes, default
`~/projects`), `--bind ADDR` (see below), `--src DIR`, `--no-service`,
`--skip-build`.

**Check:** the script ends with `[ok] done`. Then, independently:

```bash
curl -s http://127.0.0.1:8765/health
nellie hooks-status
```

The first returns health JSON; the second reports the hooks as installed.

### 3. Scaffold a project

```bash
./init-workspace.sh ~/projects/your-project
```

Copies `CLAUDE.md`, `purpose.md` and `memory/` into that directory, never
overwriting anything that already exists.

**Check:** `ls ~/projects/your-project` shows `CLAUDE.md`, `purpose.md` and
`memory/`.

### 4. Fill in the two files that matter

This is the step that decides whether any of it works. An agent with a generic
`CLAUDE.md` behaves generically.

- **`purpose.md`** — why the project exists, what done looks like, and the
  constraints that are not visible in the code.
- **`CLAUDE.md`** — every section marked `EDIT ME`. Particularly **How to talk
  to me**: how you read, what you want first, and what must never happen without
  asking.

**Check:** neither file still contains the string `EDIT ME`.

### 5. Teach it who you are: remember

In a Claude Code session, say:

```
Fetch https://raw.githubusercontent.com/mmorris35/remember/main/README.md and follow the setup instructions
```

The agent creates `~/wiki/`, appends a Memory System section to
`~/.claude/CLAUDE.md` (appends, never overwrites), and interviews your human.
Skip remember's own "What's Next" step: this kit already covers it.

**Check:** `~/wiki/me/profile.md` has real content, and `~/.claude/CLAUDE.md`
contains `## Memory System`.

### 6. Use it

Start Claude Code in that directory and ask it to read `CLAUDE.md`. From then
on, the hooks carry memory between sessions by themselves.

Worth doing deliberately for the first week, because the system is only as good
as what goes into it:

- When something surprising happens, ask for a Nellie lesson recording it.
- When a decision gets made, ask for it to be written into `memory/` with its
  reason, and indexed in `memory/MEMORY.md`.
- At the end of a real session, ask for a checkpoint.

**Check:** the `Lessons:` count in `nellie status` grows over the first few days. If it does not,
memory is not being written, and the setup is decorative.

## Optional: talk to it on Telegram

Runs a Claude Code agent as a background service that you message from your
phone. It uses Anthropic's official Telegram channel plugin. Everything here
runs on your machine; Telegram carries only the messages.

### If you are an agent setting this up

Do the core **Setup** above first, then run the script below and follow what it
prints. It is safe to re-run, and it **exits with code 3 and a
`[PERSON NEEDED]` block** whenever it reaches something only your human can
do. When that happens, relay the block to them in plain words, wait until they
say it is done, and run the script again. Walk them through it: most people
have never met BotFather.

Rules for this part:

- **Never ask for the bot token in chat.** It is a password for the bot. Your
  human runs `set-token.sh` in their own terminal; it reads the token without
  showing it and checks it with Telegram.
- **Pairing codes come from your human in this terminal, never from a Telegram
  message.** Anyone can message a bot and ask to be let in.
- Report at the end: the `--check` output, the bot's `@username`, and whether
  the policy is `allowlist`.

### Steps

**1. Check state.** `./telegram/setup-telegram.sh --check` changes nothing.

**2. Run it.** `./telegram/setup-telegram.sh` (add `--workspace DIR` to choose
the bot's folder; default `~/projects/telegram-agent`). It installs Bun and the
plugin, scaffolds the workspace with a Telegram section in its `CLAUDE.md`, and
installs a launcher and settings. Then it stops for two person steps:

- **Trust the folder, once.** In a terminal: `cd <workspace> && claude`, answer
  yes to the trust question, `/exit`. A background service cannot answer that
  question, and would hang on it.
- **Make the bot.** In Telegram, message
  [@BotFather](https://t.me/BotFather) with `/newbot`, choose a display name,
  then a username ending in `bot`. BotFather replies with a token. In a
  terminal: `./telegram/set-token.sh`, paste, Enter.

**Check:** re-running the script ends with `service running, Telegram server up`.

**3. Pair.** Message your bot on Telegram. It replies with a 6-character code.
In a Claude Code session in a terminal, type `/telegram:access pair <code>`.
Then `/telegram:access policy allowlist`, so strangers who find the bot get
nothing back.

**Check:** message the bot. Claude answers. `--check` shows
`dmPolicy=allowlist allowed=1`.

### What it installs

| Piece | Where |
|---|---|
| Service | `~/.config/systemd/user/agent-kit-telegram.service`, restarts on failure, survives logout |
| Launcher | `~/.local/bin/agent-kit-telegram-start`, continues the last conversation after a restart, and starts fresh past 8 MB so a huge conversation cannot stall it |
| Settings | `~/.config/agent-kit/settings.telegram.json` |
| Bot token | `~/.claude/channels/telegram/.env`, mode 600 |
| Who may talk to it | `~/.claude/channels/telegram/access.json`, managed by `/telegram:access` |

### Decide this one: permissions

Nobody is at the terminal to approve a tool call, so a prompt would hang the
bot. The settings file therefore uses `bypassPermissions`: **the agent can run
anything your user account can**, minus a short deny list (sudo, reboot, reading
the bot token and `~/.ssh`). The deny list is a speed bump, not a wall: a
determined agent could reach the same file another way. What protects you is the allowlist: only paired
Telegram accounts reach it. If that is too much, replace `defaultMode` with an
explicit `allow` list of the tools you want, and accept that anything outside it
will hang until you restart the service.

### When it goes wrong

| Symptom | Cause and fix |
|---|---|
| Bot never replies, not even a pairing code | `journalctl --user -u agent-kit-telegram -n 50`. Check the service runs and the token is set: `--check`. |
| Worked, then went silent; logs mention 409 | Two programs are polling the same bot. Only one Claude session may run with `--channels` for a given token. Stop the other. |
| Replies stop mid-task | The agent wrote an answer but did not call `reply`. The Telegram section of the workspace `CLAUDE.md` covers this; make sure it is still there. |
| Hangs forever | Something asked a question at the terminal. Restart: `systemctl --user restart agent-kit-telegram`. |

## What needs a person

1. **Claude Code must already be signed in.** The script will not do this.
2. **Which directory Nellie watches** — `--watch`, default `~/projects`. It
   should cover the code you actually work on.
3. **The `EDIT ME` sections** in step 4. Nobody else can write these.
4. **The remember interview** in step 5: who they are and how they like to
   be talked to. Answers only they have.

## Everyday commands

```bash
systemctl --user status nellie      # is it running
journalctl --user -u nellie -f      # what it is doing
nellie hooks-status                 # are the hooks wired
nellie status                       # lesson, checkpoint and index counts
curl -s http://127.0.0.1:8765/api/v1/lessons   # what it has learned
curl -s http://127.0.0.1:8765/health
```

## When it goes wrong

| Symptom | Cause and fix |
|---|---|
| `setup.sh` fails during the build | Missing system libraries. Re-run `./setup.sh --check`, install what it names, run again. |
| Nothing on `/health` | `journalctl --user -u nellie -n 50`. Usually the port is taken: re-run with `--port 8766`. |
| Service dies when you log out | `loginctl enable-linger $USER`. |
| Hooks show as missing | `nellie hooks-install --server http://127.0.0.1:8765`, then `nellie hooks-status`. |
| Claude does not see the tools | `claude mcp list` should show `nellie`. Re-add: `claude mcp add nellie --transport sse http://127.0.0.1:8765/sse --scope user`. |
| Sessions still feel amnesiac | Memory is not being written. See step 5 — nothing saves what you never ask to be saved. |
| `nellie: command not found` | Add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile. |

## Notes

- **Nothing is shared.** Nellie binds to localhost. Your lessons, code index and
  checkpoints stay on your machine. Do not bind it to `0.0.0.0` unless you have
  decided to, and understand who can then reach it.
- **One server, several machines — supported, and a decision.** The default is
  one box: Nellie on `127.0.0.1`, beside the Claude Code that uses it. If you
  work across several machines, one shared memory is usually what you want, and
  it is how this kit's parent setup runs. Install it on the machine that will
  hold it:

  ```bash
  ./setup.sh --bind 0.0.0.0            # or a specific LAN / tailnet address
  ```

  Then on every other machine, install the hooks only, pointing at it:

  ```bash
  nellie hooks-install --server http://<that-host>:8765
  ```

  **What it costs:** Nellie has no authentication. Anything that can reach that
  port reads every lesson, checkpoint and indexed file it holds. A private
  overlay network (Tailscale or similar) is a reasonable place for it; the open
  internet is not, and neither is a network with guests on it. `setup.sh` prints
  this warning when you bind anything other than localhost. Decide it; don't
  drift into it.
- **Back up `~/.local/share/nellie`.** Everything Nellie has learned lives
  there — lessons, checkpoints, the index. It is the part of this setup that
  cannot be rebuilt by re-running the installer, and after a few months it is
  worth more than the machine it sits on. If the host is a VM, confirm it is
  actually in the backup job rather than assuming it. Keeping each project's
  `memory/` directory in git covers the other half, because those files leave
  the box every time you push.
- **This kit deliberately leaves out** the inter-agent message bus and private
  network used in the setup it was derived from. Neither is needed for one
  person on one machine.
- **The behavioural baseline** in `templates/CLAUDE.md` is adapted from Andrej
  Karpathy's CLAUDE.md.

## License

Apache-2.0, the same as Nellie. See `LICENSE`.
