#!/usr/bin/env bash
# Fetches channel info from the Wildix API by raw channel ID.
# Usage: ID_TOKEN=<token> get-chat-by-id.sh <rawIdOrChannelIdOrUrl>
set -euo pipefail

ID_TOKEN="${ID_TOKEN:?ID_TOKEN env var required. Usage: ID_TOKEN=<token> get-chat-by-id.sh <rawIdOrChannelIdOrUrl>}"
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
