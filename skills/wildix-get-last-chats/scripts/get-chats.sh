#!/usr/bin/env bash
# Usage: get-chats.sh [limit] [offset]
#   limit:  number of chats to return (default: 30)
#   offset: skip this many chats (default: 0)
set -euo pipefail

# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
for _d in "$(dirname "$0")/../.." "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2
LIMIT="${1:-30}"
OFFSET="${2:-0}"

curl -sf \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H "Authorization: Bearer $ID_TOKEN" \
  "https://api.x-bees.com/v2/conversations/channels?limit=$LIMIT&offset=$OFFSET"
