#!/usr/bin/env bash
# Usage: send-message.sh <channelId> <text> [--token <tok>] [--reply-to <messageId>] [--attach <json>] ...
#
#   --token      ID_TOKEN (user) or leave blank to use BOT_TOKEN from .env
#   --reply-to   messageId of the message to reply/quote (same channel)
#   --attach     MessageAttachment JSON string (repeat for multiple files;
#                use upload-file.sh to get this JSON)
set -euo pipefail

CHANNEL_ID="${1:?Usage: send-message.sh <channelId> <text> [--token <tok>] [--reply-to <msgId>] [--attach <json>] ...}"
TEXT="${2:?text required}"
shift 2

TOKEN=""
REPLY_TO=""
ATTACHMENTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)    TOKEN="$2";     shift 2 ;;
    --reply-to) REPLY_TO="$2";  shift 2 ;;
    --attach)   ATTACHMENTS+=("$2"); shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Normalise channelId: strip URL prefix and type prefix (e.g. group:abc → abc)
CHANNEL_ID=$(echo "$CHANNEL_ID" | sed 's|.*/inbox/||' | sed 's/^[^:]*://')

API_BASE="https://api.x-bees.com"

if [[ -z "$TOKEN" ]]; then
  TOKEN="${ID_TOKEN:-}"
fi

if [[ -z "$TOKEN" ]]; then
  ENV_FILE="$(dirname "$0")/../.env"
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
  TOKEN="${BOT_TOKEN:-}"
fi

if [[ -z "$TOKEN" ]]; then
  echo "Error: no token available. Set BOT_TOKEN in .env or pass --token." >&2
  exit 1
fi

# If replying, fetch the original message to build the required quote object
QUOTE_JSON=""
if [[ -n "$REPLY_TO" ]]; then
  MSG_RESP=$(curl -sf \
    "${API_BASE}/v2/conversations/channels/${CHANNEL_ID}/messages/${REPLY_TO}" \
    -H "User-Agent: wildix-agent-skills/1.1.0" \
    -H "Authorization: Bearer ${TOKEN}" || true)
  # Extract the message object (response may be wrapped or plain)
  QUOTE_JSON=$(echo "$MSG_RESP" | python3 -c "
import json, sys
d = json.load(sys.stdin)
msg = d.get('message', d)
q = {
  'messageId': msg['messageId'],
  'channelId': msg['channelId'],
  'createdAt': msg['createdAt'],
  'user': msg['user'],
}
if msg.get('text'):
    q['text'] = msg['text']
if msg.get('attachments'):
    q['attachments'] = msg['attachments']
print(json.dumps(q))
" 2>/dev/null || echo "")
  if [[ -z "$QUOTE_JSON" ]]; then
    echo "Error: could not fetch original message for --reply-to ${REPLY_TO}. Check the messageId and token." >&2
    exit 1
  fi
fi

# Build JSON body via python3 to handle escaping correctly
BODY=$(python3 - "$TEXT" "$QUOTE_JSON" "${ATTACHMENTS[@]+"${ATTACHMENTS[@]}"}" <<'EOF'
import json, sys

text = sys.argv[1]
quote_raw = sys.argv[2]
attachments_raw = sys.argv[3:]

body = {"text": text}

if quote_raw:
    body["quote"] = json.loads(quote_raw)

if attachments_raw:
    body["attachments"] = [json.loads(a) for a in attachments_raw]

print(json.dumps(body))
EOF
)

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -X POST \
  "${API_BASE}/v2/conversations/channels/${CHANNEL_ID}/messages" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_BODY=$(echo "$RESPONSE" | awk 'NR>1{print prev} {prev=$0}')
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "Sent (HTTP $HTTP_CODE): $HTTP_BODY"
else
  echo "Error (HTTP $HTTP_CODE): $HTTP_BODY" >&2
  exit 1
fi
