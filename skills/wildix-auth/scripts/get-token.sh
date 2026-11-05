#!/bin/bash
# Returns a valid IdToken for <email>. Auto-refreshes if expired.
# After refresh, validates token via Wildix API.
# Usage: bash get-token.sh <email>
# Exit codes: 0=ok, 1=no tokens/error, 2=token invalid (re-auth required)
set -e
source "$(dirname "$0")/config.sh"

EMAIL="${1:?Usage: $0 <email>}"

TOKEN_FILE=$(wildix_token_file "$EMAIL")

if [ ! -f "$TOKEN_FILE" ]; then
  echo "No tokens for $EMAIL. Run wildix-auth skill to authenticate." >&2
  exit 1
fi

SAVED_AT=$(jq -r '.savedAt' "$TOKEN_FILE")
EXPIRES_IN=$(jq -r '.ExpiresIn' "$TOKEN_FILE")
SAVED_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$SAVED_AT" +%s 2>/dev/null || date -d "$SAVED_AT" +%s 2>/dev/null)
NOW_TS=$(date +%s)
ELAPSED=$((NOW_TS - SAVED_TS))

REFRESHED=0
if [ "$ELAPSED" -ge "$((EXPIRES_IN - 60))" ]; then
  echo "Token expired (${ELAPSED}s old). Refreshing..." >&2
  bash "$(dirname "$0")/refresh-tokens.sh" "$EMAIL" >&2
  REFRESHED=1
fi

ID_TOKEN=$(jq -r '.IdToken' "$TOKEN_FILE")

if [ "$REFRESHED" = "1" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "User-Agent: wildix-agent-skills/1.1.0" \
    "$WILDIX_API_URL/v2/conversations/inbox/state" \
    -H "Authorization: Bearer $ID_TOKEN")
  if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo "Refreshed token rejected by API (HTTP $HTTP_CODE). Re-authentication required." >&2
    exit 2
  fi
fi

echo "$ID_TOKEN"
