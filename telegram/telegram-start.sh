#!/usr/bin/env bash
# agent-kit telegram launcher — what the systemd service runs.
#
# Starts Claude Code in the bot's workspace with the Telegram channel attached,
# continuing the previous conversation if there is one, so a restart does not
# wipe what the bot was in the middle of.
#
# Installed to ~/.local/bin/agent-kit-telegram-start by setup-telegram.sh.

set -uo pipefail

WORKSPACE="${AGENT_KIT_TELEGRAM_WORKSPACE:?set by the service}"
SETTINGS="${AGENT_KIT_TELEGRAM_SETTINGS:?set by the service}"
CLAUDE="$(command -v claude)" || { echo "claude not on PATH" >&2; exit 1; }

# A conversation that grows past this forces compaction on every turn and the
# bot stops answering promptly. Past the ceiling, the old conversation is set
# aside (renamed, not deleted) and the bot starts fresh. Nellie and memory/
# carry what matters across the break.
MAX_SESSION_BYTES="${AGENT_KIT_TELEGRAM_MAX_SESSION_BYTES:-8388608}"   # 8 MiB

# AskUserQuestion draws a multiple-choice prompt in a terminal nobody is
# watching. On Telegram there is no one to click it, so the turn hangs for
# good. Removing the tool is the only reliable fix.
ARGS=(--disallowedTools AskUserQuestion
      --settings "$SETTINGS"
      --channels plugin:telegram@claude-plugins-official)

cd "$WORKSPACE" || exit 1

# Claude Code keeps each directory's conversations under a name derived from
# its path: every non-alphanumeric character becomes '-'.
PROJECT_DIR="$HOME/.claude/projects/$(pwd | sed 's/[^A-Za-z0-9]/-/g')"
LATEST="$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1 || true)"

if [[ -n "$LATEST" ]]; then
  size="$(stat -c %s "$LATEST" 2>/dev/null || echo 0)"
  if (( size > MAX_SESSION_BYTES )); then
    mv -f "$LATEST" "$LATEST.archived-$(date +%Y%m%dT%H%M%S)"
    echo "$(date -Iseconds) conversation was ${size}B, set aside; starting fresh"
  else
    echo "$(date -Iseconds) continuing previous conversation (${size}B)"
    exec "$CLAUDE" --continue "${ARGS[@]}"
  fi
fi

echo "$(date -Iseconds) starting fresh"
exec "$CLAUDE" "${ARGS[@]}"
