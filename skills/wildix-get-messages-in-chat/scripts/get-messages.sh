#!/usr/bin/env bash
# Usage: ID_TOKEN=<token> get-messages.sh <channelId> [limit] [offset]
#   channelId: raw ID, type:rawId (e.g. group:abc123), or https://app.x-bees.com/inbox/<rawId> URL
#   limit:  number of messages to return (default: 50)
#   offset: skip this many messages (default: 0); use for pagination
set -euo pipefail

ID_TOKEN="${ID_TOKEN:?ID_TOKEN env var required. Usage: ID_TOKEN=<token> get-messages.sh <channelId> [limit] [offset]}"
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
