#!/usr/bin/env bash
# Edit or delete your own x-bees message, as the user whose IdToken is given.
# Usage: ID_TOKEN=<token> update-message.sh edit   <channelId> <messageId> <text> [--markdown]
#        ID_TOKEN=<token> update-message.sh delete <channelId> <messageId>
#
#   edit    PATCH  /v2/conversations/channels/{channelId}/messages/{messageId}  {"set":{"text":...}}
#   delete  DELETE /v2/conversations/channels/{channelId}/messages/{messageId}
#
#   --markdown  the new text is Markdown ({"set":{"markdown":true}})
#
# The message must be the user's own: it is read first, and nothing is changed when its author is
# someone else. channelId may be an inbox URL, a full channelId (group:abc) or a raw id.
set -euo pipefail

USAGE="Usage: ID_TOKEN=<token> update-message.sh <edit|delete> <channelId> <messageId> [text] [--markdown]"
ACTION="${1:?$USAGE}"
CHANNEL_ID="${2:?$USAGE}"
MESSAGE_ID="${3:?$USAGE}"
shift 3

ID_TOKEN="${ID_TOKEN:?ID_TOKEN env var required (get it with the wildix-auth skill)}"

TEXT=""
HAVE_TEXT=0
MARKDOWN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --markdown) MARKDOWN=1; shift ;;
    --*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) if [[ $HAVE_TEXT -eq 1 ]]; then echo "Error: more than one text argument" >&2; exit 1; fi
       TEXT="$1"; HAVE_TEXT=1; shift ;;
  esac
done

case "$ACTION" in
  edit)   [[ $HAVE_TEXT -eq 1 && -n "$TEXT" ]] || { echo "Error: text required for 'edit'" >&2; exit 1; } ;;
  delete) [[ $HAVE_TEXT -eq 0 ]] || { echo "Error: 'delete' takes no text" >&2; exit 1; } ;;
  *) echo "Error: unknown action '$ACTION'. $USAGE" >&2; exit 1 ;;
esac

# Normalise channelId: strip URL prefix and type prefix (group:abc -> abc)
CHANNEL_ID=$(echo "$CHANNEL_ID" | sed 's|.*/inbox/||' | sed 's/^[^:]*://')

URL="https://api.x-bees.com/v2/conversations/channels/${CHANNEL_ID}/messages/${MESSAGE_ID}"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
H=(-H "User-Agent: wildix-agent-skills/1.1.0" -H "Authorization: Bearer ${ID_TOKEN}")

# 1. Read the message and check that it is the user's own.
CODE=$(curl -sS -o "$OUT" -w '%{http_code}' "${H[@]}" "$URL")
if [[ "$CODE" != 2* ]]; then
  echo "Error: HTTP $CODE reading the message (wrong channel or messageId, or no access)" >&2
  cat "$OUT" >&2; echo >&2
  exit 1
fi
ME=$(python3 - "$ID_TOKEN" <<'PY'
import base64, json, sys
p = sys.argv[1].split(".")[1]
p += "=" * (-len(p) % 4)
print(json.loads(base64.urlsafe_b64decode(p)).get("email", "").lower())
PY
)
AUTHOR=$(python3 - "$OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
m = d.get("message", d)
print((m.get("user") or {}).get("email", "").lower())
PY
)
if [[ -z "$ME" || -z "$AUTHOR" || "$ME" != "$AUTHOR" ]]; then
  echo "Error: the message is not yours (author: ${AUTHOR:-unknown}, you: ${ME:-unknown}). Nothing was changed." >&2
  exit 2
fi

# 2. Change it.
if [[ "$ACTION" == edit ]]; then
  BODY=$(python3 - "$TEXT" "$MARKDOWN" <<'PY'
import json, sys
text, md = sys.argv[1], sys.argv[2] == "1"
s = {"text": text}
if md:
    s["markdown"] = True
print(json.dumps({"set": s}))
PY
)
  CODE=$(curl -sS -o "$OUT" -w '%{http_code}' "${H[@]}" -X PATCH -H "Content-Type: application/json" -d "$BODY" "$URL")
else
  CODE=$(curl -sS -o "$OUT" -w '%{http_code}' "${H[@]}" -X DELETE "$URL")
fi

if [[ "$CODE" != 2* ]]; then
  echo "Error: HTTP $CODE from x-bees API ($ACTION)" >&2
  cat "$OUT" >&2; echo >&2
  exit 1
fi
if [[ -s "$OUT" ]]; then cat "$OUT"; echo; else echo "{\"ok\":true,\"action\":\"$ACTION\"}"; fi
