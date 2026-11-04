#!/usr/bin/env bash
# Usage: get-messages.sh <channelId> [limit] [offset]
#   channelId: raw ID, type:rawId (e.g. group:abc123), or https://app.x-bees.com/inbox/<rawId> URL
#   limit:  number of messages to return (default: 50)
#   offset: skip this many messages (default: 0); use for pagination
set -euo pipefail

# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
for _d in "$(dirname "$0")/../.." "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2
CHANNEL_ID="${1:?channelId required}"
LIMIT="${2:-50}"
OFFSET="${3:-0}"

# Strip URL (https://app.x-bees.com/inbox/abc123 → abc123) then type prefix (group:abc123 → abc123)
RAW_ID="${CHANNEL_ID##*/}"
RAW_ID="${RAW_ID##*:}"

curl -sf \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H "Authorization: Bearer $ID_TOKEN" \
  "https://api.x-bees.com/v2/conversations/channels/$RAW_ID/messages?limit=$LIMIT&offset=$OFFSET"
