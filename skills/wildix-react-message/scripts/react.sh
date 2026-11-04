#!/usr/bin/env bash
# Add, remove or list reactions on an x-bees message, as the user whose IdToken is given.
# Usage: ID_TOKEN=<token> react.sh <add|remove|list> <channelId> <messageId> [reactionType]
#
#   add     POST   /v2/conversations/channels/{channelId}/messages/{messageId}/reactions
#   remove  DELETE /v2/conversations/channels/{channelId}/messages/{messageId}/reactions/{reactionType}
#   list    GET    /v2/conversations/channels/{channelId}/messages/{messageId}/reactions
#
# channelId may be an inbox URL, a full channelId (group:abc) or a raw id.
set -euo pipefail

USAGE="Usage: ID_TOKEN=<token> react.sh <add|remove|list> <channelId> <messageId> [reactionType]"
ACTION="${1:?$USAGE}"
CHANNEL_ID="${2:?$USAGE}"
MESSAGE_ID="${3:?$USAGE}"
TYPE="${4:-}"

ID_TOKEN="${ID_TOKEN:?ID_TOKEN env var required (get it with the wildix-auth skill)}"

ALLOWED="clap confused eyes heart slightly_smiling_face smiley thumbsdown thumbsup white_check_mark"

case "$ACTION" in
  add|remove)
    if [[ -z "$TYPE" ]]; then
      echo "Error: reactionType required for '$ACTION'. Allowed: $ALLOWED" >&2
      exit 1
    fi
    if ! [[ " $ALLOWED " == *" $TYPE "* ]]; then
      echo "Error: unknown reactionType '$TYPE'. Allowed: $ALLOWED" >&2
      exit 1
    fi
    ;;
  list) ;;
  *) echo "Error: unknown action '$ACTION'. $USAGE" >&2; exit 1 ;;
esac

# Normalise channelId: strip URL prefix and type prefix (group:abc -> abc)
CHANNEL_ID=$(echo "$CHANNEL_ID" | sed 's|.*/inbox/||' | sed 's/^[^:]*://')

BASE="https://api.x-bees.com/v2/conversations/channels/${CHANNEL_ID}/messages/${MESSAGE_ID}/reactions"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

COMMON=(-sS -o "$OUT" -w '%{http_code}' -H "User-Agent: wildix-agent-skills/1.1.0" -H "Authorization: Bearer ${ID_TOKEN}")

case "$ACTION" in
  add)
    CODE=$(curl "${COMMON[@]}" -X POST -H "Content-Type: application/json" \
      -d "{\"reactionType\":\"${TYPE}\"}" "$BASE") ;;
  remove)
    CODE=$(curl "${COMMON[@]}" -X DELETE "${BASE}/${TYPE}") ;;
  list)
    CODE=$(curl "${COMMON[@]}" "${BASE}?limit=300") ;;
esac

if [[ "$CODE" != 2* ]]; then
  echo "Error: HTTP $CODE from x-bees API ($ACTION $TYPE)" >&2
  cat "$OUT" >&2
  echo >&2
  exit 1
fi

if [[ -s "$OUT" ]]; then cat "$OUT"; echo; else echo "{\"ok\":true,\"action\":\"$ACTION\"}"; fi
