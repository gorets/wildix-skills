#!/usr/bin/env bash
# Fetches channel info from the Wildix API by raw channel ID.
# Usage: get-chat-by-id.sh <rawIdOrChannelIdOrUrl>
set -euo pipefail

# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
for _d in "$(dirname "$0")/../.." "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2
INPUT="${1:?rawIdOrChannelIdOrUrl required}"

# Extract raw ID: strip URL (https://app.x-bees.com/inbox/abc123 → abc123)
# and strip type prefix (group:abc123 → abc123)
RAW_ID="${INPUT##*/}"
RAW_ID="${RAW_ID##*:}"

RESPONSE=$(curl -sf \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H "Authorization: Bearer $ID_TOKEN" \
  "https://api.x-bees.com/v2/conversations/channels/$RAW_ID")

if [[ -z "$RESPONSE" ]]; then
  echo "Error: channel '$RAW_ID' not found" >&2
  exit 1
fi

echo "$RESPONSE"
