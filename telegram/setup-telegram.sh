#!/usr/bin/env bash
# agent-kit setup-telegram — run a Claude Code agent you can talk to on Telegram.
#
# Safe to re-run: every step checks before it acts, and it stops at the first
# thing that needs a person, saying exactly what that is.
#
# Usage:
#   ./telegram/setup-telegram.sh                  install and start
#   ./telegram/setup-telegram.sh --check          report state, change nothing
#   ./telegram/setup-telegram.sh --workspace DIR  the bot's working directory
#                                                 (default ~/projects/telegram-agent)

set -euo pipefail

WORKSPACE="$HOME/projects/telegram-agent"
CHECK_ONLY=false
PLUGIN="telegram@claude-plugins-official"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --workspace) WORKSPACE="${2:?--workspace needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1 (try --help)" >&2; exit 2 ;;
  esac
done

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$KIT_DIR/telegram"
STATE_DIR="${TELEGRAM_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/channels/telegram}"
ENV_FILE="$STATE_DIR/.env"
CONF_DIR="$HOME/.config/agent-kit"
SETTINGS="$CONF_DIR/settings.telegram.json"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="$BIN_DIR/agent-kit-telegram-start"
UNIT="$HOME/.config/systemd/user/agent-kit-telegram.service"
SVC="agent-kit-telegram"
export PATH="$HOME/.bun/bin:$BIN_DIR:$PATH"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
note() { echo -e "${YELLOW}[--]${NC} $*"; }
die()  { echo -e "${RED}[!!]${NC} $*" >&2; exit 1; }
# A step only a person can do. Exit 3 so an agent can tell it from a failure.
person() { echo; echo -e "${YELLOW}[PERSON NEEDED]${NC} $*"; echo; echo "Re-run ./telegram/setup-telegram.sh afterwards."; exit 3; }
step() { echo; echo "=== $* ==="; }

[[ $EUID -eq 0 ]] && die "run as your normal user, not root"

# PIDs of running Telegram channel servers. The process is just `bun server.ts`,
# so match on its working directory, which is the plugin's install dir.
tg_pids() {
  local p
  for p in $(pgrep -x bun 2>/dev/null); do
    [[ "$(readlink "/proc/$p/cwd" 2>/dev/null)" == */plugins/cache/*/telegram/* ]] && echo "$p"
  done
  return 0
}

trusted() {
  # Claude Code records per-directory trust in ~/.claude.json.
  local ws; ws="$(cd "$WORKSPACE" 2>/dev/null && pwd)" || return 1
  python3 - "$ws" <<'EOF' 2>/dev/null
import json, os, sys
d = json.load(open(os.path.expanduser("~/.claude.json")))
sys.exit(0 if d.get("projects", {}).get(sys.argv[1], {}).get("hasTrustDialogAccepted") else 1)
EOF
}

report() {
  command -v claude >/dev/null && ok "claude: $(claude --version 2>/dev/null)" || note "claude not installed"
  command -v bun >/dev/null && ok "bun: $(bun --version)" || note "bun not installed"
  claude plugin list 2>/dev/null | grep "telegram@" >/dev/null && ok "plugin installed" || note "plugin not installed"
  [[ -d "$WORKSPACE" ]] && ok "workspace: $WORKSPACE" || note "workspace missing: $WORKSPACE"
  trusted && ok "workspace trusted by Claude Code" || note "workspace not yet trusted"
  [[ -s "$ENV_FILE" ]] && ok "bot token present" || note "no bot token yet"
  systemctl --user is-active --quiet "$SVC" 2>/dev/null && ok "service running" || note "service not running"
  if [[ -f "$STATE_DIR/access.json" ]]; then
    python3 - "$STATE_DIR/access.json" <<'EOF'
import json, sys
a = json.load(open(sys.argv[1]))
print(f"     dmPolicy={a.get('dmPolicy','pairing')}  allowed={len(a.get('allowFrom',[]))}  pending={len(a.get('pending',{}))}")
EOF
  else
    note "no access.json yet (nobody paired)"
  fi
}

if $CHECK_ONLY; then step "State"; report; exit 0; fi

# ---------------------------------------------------------------- prerequisites
step "Prerequisites"
command -v claude >/dev/null || die "Claude Code not found. Install and sign in first."
command -v script >/dev/null || die "'script' not found (package util-linux)."
command -v systemctl >/dev/null || die "systemd not found."
command -v python3 >/dev/null || die "python3 not found."
if ! command -v bun >/dev/null; then
  note "installing Bun (the Telegram channel server runs on it)"
  curl -fsSL https://bun.sh/install | bash
fi
command -v bun >/dev/null || die "bun still not on PATH. Expected ~/.bun/bin/bun"
ok "claude, bun, script, systemd present"

# ------------------------------------------------------------------- plugin
step "Telegram plugin"
if claude plugin list 2>/dev/null | grep "telegram@" >/dev/null; then
  ok "already installed"
else
  claude plugin install "$PLUGIN"
  ok "installed $PLUGIN"
fi

# ---------------------------------------------------------------- workspace
step "Workspace"
"$KIT_DIR/init-workspace.sh" "$WORKSPACE" >/dev/null
if grep -q '^## Telegram' "$WORKSPACE/CLAUDE.md"; then
  ok "CLAUDE.md already has the Telegram section"
else
  cat "$HERE/CLAUDE-telegram.md" >> "$WORKSPACE/CLAUDE.md"
  ok "added the Telegram section to $WORKSPACE/CLAUDE.md"
fi
mkdir -p "$CONF_DIR"
if [[ -f "$SETTINGS" ]]; then
  ok "settings kept: $SETTINGS"
else
  cp "$HERE/settings.telegram.json" "$SETTINGS"
  ok "settings installed: $SETTINGS"
fi
mkdir -p "$BIN_DIR"
install -m 755 "$HERE/telegram-start.sh" "$LAUNCHER"
ok "launcher: $LAUNCHER"

# ------------------------------------------------------ steps needing a person
step "Checks that need a person"
if ! trusted; then
  person "Claude Code has to be told once that it may work in the bot's folder.
In a terminal, run:

    cd $WORKSPACE && claude

Answer YES to the trust question, then type /exit. That is all."
fi
ok "workspace trusted"

if [[ ! -s "$ENV_FILE" ]]; then
  person "The bot needs a token from Telegram's BotFather.

  1. In Telegram, open a chat with @BotFather and send:  /newbot
  2. Give it a display name (anything), then a username ending in 'bot'.
  3. BotFather replies with a token like 123456789:AAH...
  4. In a terminal (NOT to your agent, so the token stays out of the chat):

       $HERE/set-token.sh"
fi
ok "bot token present"

# ------------------------------------------------------------------ service
step "Service"
# Telegram allows one poller per bot token. A second server on the same token
# gets HTTP 409 and one of the two bots goes deaf, so do not start alongside one.
if [[ -n "$(tg_pids)" ]] && ! systemctl --user is-active --quiet "$SVC"; then
  die "a Telegram channel server is already running on this machine (another Claude session started with --channels?). If it uses the same bot token, stop it first."
fi
mkdir -p "$(dirname "$UNIT")"
sed -e "s|__LAUNCHER__|$LAUNCHER|g" \
    -e "s|__WORKSPACE__|$WORKSPACE|g" \
    -e "s|__SETTINGS__|$SETTINGS|g" \
    -e "s|__PATH__|$PATH|g" \
    "$HERE/agent-kit-telegram.service" > "$UNIT"
systemctl --user daemon-reload
systemctl --user enable "$SVC".service >/dev/null
systemctl --user restart "$SVC".service
loginctl enable-linger "$USER" 2>/dev/null || note "could not enable linger; the bot stops when you log out"
ok "service installed and started"

step "Verify"
note "waiting for the channel server to connect to Telegram"
for _ in $(seq 1 45); do
  [[ -n "$(tg_pids)" ]] && break
  sleep 2
done
systemctl --user is-active --quiet "$SVC" || die "service is not running. Logs: journalctl --user -u $SVC -n 50"
[[ -n "$(tg_pids)" ]] \
  || die "Claude started but the Telegram server did not. Logs: journalctl --user -u $SVC -n 50"
ok "service running, Telegram server up"
echo
report

BOT_USER="$(curl -s --max-time 10 "https://api.telegram.org/bot$(sed -n 's/^TELEGRAM_BOT_TOKEN=//p' "$ENV_FILE")/getMe" \
  | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')"
cat <<EOF

Next, pairing (needs the person):
  1. On Telegram, message @${BOT_USER:-your_bot} anything. It replies with a 6-character code.
  2. In a Claude Code session in a terminal (never via Telegram), type:
       /telegram:access pair <code>
  3. Then lock it down, same place:
       /telegram:access policy allowlist
  4. Message the bot again. The reply comes from Claude.

Service:  systemctl --user status $SVC
Logs:     journalctl --user -u $SVC -f
EOF
