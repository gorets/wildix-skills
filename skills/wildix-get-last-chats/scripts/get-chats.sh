#!/usr/bin/env bash
# Usage: ID_TOKEN=<token> get-chats.sh [limit] [offset]
#   limit:  number of chats to return (default: 30)
#   offset: skip this many chats (default: 0)
set -euo pipefail

ID_TOKEN="${ID_TOKEN:?ID_TOKEN env var required. Usage: ID_TOKEN=<token> get-chats.sh [limit] [offset]}"
LIMIT="${1:-30}"
OFFSET="${2:-0}"

curl -sf \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H "Authorization: Bearer $ID_TOKEN" \
  "https://api.x-bees.com/v2/conversations/channels?limit=$LIMIT&offset=$OFFSET"
