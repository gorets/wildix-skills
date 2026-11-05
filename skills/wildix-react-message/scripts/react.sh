#!/usr/bin/env bash
# Add, remove or list reactions on an x-bees message, as the user whose IdToken is given.
# Usage: react.sh <add|remove|list> <channelId> <messageId> [reactionType]
#
#   add     POST   /v2/conversations/channels/{channelId}/messages/{messageId}/reactions
#   remove  DELETE /v2/conversations/channels/{channelId}/messages/{messageId}/reactions/{reactionType}
#   list    GET    /v2/conversations/channels/{channelId}/messages/{messageId}/reactions
#
# channelId may be an inbox URL, a full channelId (group:abc) or a raw id.
set -euo pipefail

USAGE="Usage: react.sh <add|remove|list> <channelId> <messageId> [reactionType]"
ACTION="${1:?$USAGE}"
CHANNEL_ID="${2:?$USAGE}"
MESSAGE_ID="${3:?$USAGE}"
TYPE="${4:-}"

# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
for _d in "$(dirname "$0")/../.." "${WILDIX_SKILLS_DIR:-}" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2

ALLOWED="clap confused eyes heart slightly_smiling_face smiley thumbsdown thumbsup white_check_mark"

case "$ACTION" in
  add|remove)
    if [[ -z "$TYPE" ]]; then
      echo "Error: reactionType required for '$ACTION'. Allowed: $ALLOWED" >&2
      exit 1
    fi
    ok=0; for _t in $ALLOWED; do [[ "$_t" == "$TYPE" ]] && ok=1; done
    if [[ $ok -ne 1 ]]; then
      echo "Error: unknown reactionType '$TYPE'. Allowed: $ALLOWED" >&2
      exit 1
    fi
    ;;
  list) ;;
  *) echo "Error: unknown action '$ACTION'. $USAGE" >&2; exit 1 ;;
esac

# Normalise the ids: a channel is an id, a "type:id" form or an inbox link (the message part of a link is
# dropped); a message is an id or a link to it. Nothing but id characters goes into the URL path, so an id that
# came from fetched data cannot rewrite the request.
CHANNEL_ID="${CHANNEL_ID%%[?#]*}"; CHANNEL_ID="${CHANNEL_ID#*/inbox/}"; CHANNEL_ID="${CHANNEL_ID%%/*}"; CHANNEL_ID="${CHANNEL_ID##*:}"
MESSAGE_ID="${MESSAGE_ID%%[?#]*}"; MESSAGE_ID="${MESSAGE_ID%/}"; MESSAGE_ID="${MESSAGE_ID##*/}"
for _v in "$CHANNEL_ID" "$MESSAGE_ID"; do
  [[ "$_v" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && "$_v" != *..* ]] || { echo "Error: not a channel or message id: $_v" >&2; exit 1; }
done

BASE="https://api.x-bees.com/v2/conversations/channels/${CHANNEL_ID}/messages/${MESSAGE_ID}/reactions"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

# The Authorization header goes to curl through a config file on a descriptor, never through argv. The
# descriptor of <( ) lives only for the command it is written in, so every curl call carries its own.
COMMON=(-sS --connect-timeout 10 --max-time 60 --proto '=https' -o "$OUT" -w '%{http_code}' -H "User-Agent: wildix-agent-skills")
auth_curl() { curl "${COMMON[@]}" -K <(printf 'header = "Authorization: Bearer %s"\n' "$ID_TOKEN") "$@"; }

case "$ACTION" in
  add)
    CODE=$(auth_curl -X POST -H "Content-Type: application/json" \
      -d "{\"reactionType\":\"${TYPE}\"}" "$BASE") ;;
  remove)
    CODE=$(auth_curl -X DELETE "${BASE}/${TYPE}") ;;
  list)
    CODE=$(auth_curl "${BASE}?limit=300") ;;
esac

if [[ "$CODE" != 2* ]]; then
  echo "Error: HTTP $CODE from x-bees API ($ACTION $TYPE)" >&2
  cat "$OUT" >&2
  echo >&2
  exit 1
fi

if [[ -s "$OUT" ]]; then cat "$OUT"; echo; else echo "{\"ok\":true,\"action\":\"$ACTION\"}"; fi
