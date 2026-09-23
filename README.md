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

Three things need your human, listed under **What needs a person**. Ask for
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

The two halves matter for different reasons. Nellie is **wide** — it searches
across everything. The files are **deep** — they carry the reasons and decisions
for one project, and they diff and review like code.

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

### 5. Use it

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

## What needs a person

1. **Claude Code must already be signed in.** The script will not do this.
2. **Which directory Nellie watches** — `--watch`, default `~/projects`. It
   should cover the code you actually work on.
3. **The `EDIT ME` sections** in step 4. Nobody else can write these.

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
