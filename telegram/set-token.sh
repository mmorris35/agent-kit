#!/usr/bin/env bash
# agent-kit set-token — give the Telegram channel its bot token.
#
# Run this YOURSELF, in your own terminal. It reads the token without echoing
# it, checks it against Telegram, and writes it where the channel reads it.
# The token never passes through an agent's conversation, so it never ends up
# in a transcript.
#
# Usage: ./telegram/set-token.sh

set -euo pipefail

STATE_DIR="${TELEGRAM_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/channels/telegram}"
ENV_FILE="$STATE_DIR/.env"

echo "Paste the token BotFather gave you (it looks like 123456789:AAH...)."
echo "Nothing will appear as you paste. Press Enter when done."
read -rs TOKEN
echo

[[ "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]] || {
  echo "That does not look like a bot token. Copy the whole thing, including the number and colon." >&2
  exit 1
}

# getMe answers with the bot's own identity, and only for a valid token.
RESP="$(curl -s --max-time 10 "https://api.telegram.org/bot${TOKEN}/getMe" || true)"
if ! grep -q '"ok":true' <<<"$RESP"; then
  echo "Telegram rejected that token. Check it in BotFather (/mybots → your bot → API Token)." >&2
  exit 1
fi
BOT_USER="$(sed -n 's/.*"username":"\([^"]*\)".*/\1/p' <<<"$RESP")"

mkdir -p "$STATE_DIR"
umask 077
printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TOKEN" > "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Token saved to $ENV_FILE (readable only by you)."
echo "Your bot is @${BOT_USER}: https://t.me/${BOT_USER}"
echo "Tell your agent: token is set, bot is @${BOT_USER}."
