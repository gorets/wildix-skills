#!/bin/bash
# Usage: get-chats-overview.sh [from_date] [to_date]
#   from_date: YYYY-MM-DD, today or yesterday; default = today
#   to_date:   YYYY-MM-DD, today or yesterday; default = from_date (single day)
# Dates and the times of the messages are in the LOCAL time zone of this computer.
# Exit codes: 0 ok, 1 error, 2 not logged in or the token was rejected.
set -euo pipefail

# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
for _d in "$(dirname "$0")/../.." "${WILDIX_SKILLS_DIR:-}" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2
# A date is YYYY-MM-DD (a real calendar day), today or yesterday, in the local time zone.
resolve_date() {
  python3 - "$1" <<'PY' || exit 1
import datetime, sys
v = sys.argv[1]
today = datetime.date.today()
try:
    d = today if v == "today" else today - datetime.timedelta(days=1) if v == "yesterday" else datetime.date.fromisoformat(v)
except ValueError:
    sys.exit("Error: a date is YYYY-MM-DD, today or yesterday: " + v)
print(d.isoformat())
PY
}
FROM_DATE=$(resolve_date "${1:-today}")
TO_DATE=$(resolve_date "${2:-$FROM_DATE}")
# The messages carry UTC times and the local day can differ from the UTC day by up to a day either way: the
# early stop below keeps a day of margin.
FROM_MARGIN=$(python3 -c 'import datetime,sys; print((datetime.date.fromisoformat(sys.argv[1]) - datetime.timedelta(days=1)).isoformat())' "$FROM_DATE")

XBEES_URL="https://api.x-bees.com"
STREAM_API_KEY="9p6289m44jum"
STREAM_DOMAIN="https://chat.wildix-chat.com"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# fetch OUTFILE curl-args...: a request that says what went wrong (a bare `curl -f` under `set -e` dies
# silently with 22). The Authorization header is given to curl on a descriptor, never in argv.
fetch() {
  local out="$1" code; shift
  code=$(curl -sS --connect-timeout 10 --max-time 60 --proto '=https' -o "$out" -w '%{http_code}' "$@") || { echo "Error: the request failed" >&2; exit 1; }
  case "$code" in
    2*) ;;
    401|403) echo "Error: HTTP $code: the token was rejected. Log in again with the wildix-auth skill." >&2; exit 2 ;;
    *) echo "Error: HTTP $code from the chat service" >&2; exit 1 ;;
  esac
}

fetch "$WORK/stream_token.json" \
  -H "User-Agent: wildix-agent-skills" \
  -K <(printf 'header = "Authorization: Bearer %s"\n' "$ID_TOKEN") \
  "$XBEES_URL/v2/conversations/token?clientId=$STREAM_API_KEY"

STREAM_TOKEN=$(jq -r '.token' "$WORK/stream_token.json")
if [ -z "$STREAM_TOKEN" ] || [ "$STREAM_TOKEN" = "null" ]; then
  echo '{"error": "Failed to get Stream token"}' >&2
  exit 1
fi

# a JWT payload is base64url: "-" and "_" must become "+" and "/" before it can be decoded
USER_ID=$(jq -R 'split(".") | .[1] | gsub("-"; "+") | gsub("_"; "/") | @base64d | fromjson | .user_id' <<< "$STREAM_TOKEN" | tr -d '"')
[ -n "$USER_ID" ] || { echo "Error: no user id in the chat token" >&2; exit 1; }

PAGE_SIZE=30
MSG_LIMIT=100
OFFSET=0
PAGE_NUM=0

echo "Fetching channels..." >&2

while true; do
  PAGE_FILE="$WORK/channels_${PAGE_NUM}.json"
  fetch "$PAGE_FILE" -X POST \
    -H "User-Agent: wildix-agent-skills" \
    -K <(printf 'header = "Authorization: %s"\n' "$STREAM_TOKEN") \
    -H "Stream-Auth-Type: jwt" \
    -H "Content-Type: application/json" \
    -d "{
      \"filter_conditions\": {\"members\": {\"\$in\": [\"$USER_ID\"]}},
      \"sort\": [{\"field\": \"last_message_at\", \"direction\": -1}],
      \"limit\": $PAGE_SIZE,
      \"offset\": $OFFSET,
      \"message_limit\": $MSG_LIMIT
    }" \
    "$STREAM_DOMAIN/channels?api_key=$STREAM_API_KEY"

  COUNT=$(jq '.channels | length' "$PAGE_FILE")
  echo "  Page $PAGE_NUM: got $COUNT channels (offset=$OFFSET)" >&2

  PAGE_NUM=$((PAGE_NUM + 1))
  OFFSET=$((OFFSET + PAGE_SIZE))

  if [ "$COUNT" -lt "$PAGE_SIZE" ]; then
    break
  fi

  OLDEST_LAST_MSG=$(jq -r '[.channels[].channel.last_message_at // ""] | map(select(. != "")) | min' "$PAGE_FILE")
  if [ -n "$OLDEST_LAST_MSG" ] && [ "${OLDEST_LAST_MSG:0:10}" \< "$FROM_MARGIN" ]; then
    echo "  Early stop: oldest last_message_at=${OLDEST_LAST_MSG:0:10} is before $FROM_DATE" >&2
    break
  fi
done

# the chat token reaches python through the environment, not through argv ("-" fills its old place)
STREAM_TOKEN="$STREAM_TOKEN" python3 - "$WORK" "$USER_ID" "$FROM_DATE" "$TO_DATE" "$PAGE_NUM" "-" "$STREAM_API_KEY" "$STREAM_DOMAIN" "$MSG_LIMIT" <<'PYEOF'
import json, sys, os, urllib.request
from datetime import datetime, timezone

workdir    = sys.argv[1]
my_user_id = sys.argv[2]
from_date  = sys.argv[3]
to_date    = sys.argv[4]
num_pages  = int(sys.argv[5])
stream_token    = os.environ["STREAM_TOKEN"]
stream_api_key  = sys.argv[7]
stream_domain   = sys.argv[8]
msg_limit       = int(sys.argv[9])

def local_date(created_at):
    """The local calendar day of a message time given in UTC (what the user means by 'today')."""
    try:
        return datetime.fromisoformat(created_at.replace('Z', '+00:00')).astimezone().strftime('%Y-%m-%d')
    except ValueError:
        return created_at[:10]

def fetch_older_messages(ch_type, ch_id, id_lt):
    url = f"{stream_domain}/channels/{ch_type}/{ch_id}/query?api_key={stream_api_key}"
    body = json.dumps({"state": True, "watch": False, "messages": {"limit": msg_limit, "id_lt": id_lt}}).encode()
    req = urllib.request.Request(url, data=body, headers={
        "Authorization": stream_token,
        "Stream-Auth-Type": "jwt",
        "User-Agent": "wildix-agent-skills",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read()).get('messages', [])

all_channels = []
for i in range(num_pages):
    with open(os.path.join(workdir, f"channels_{i}.json")) as f:
        all_channels.extend(json.load(f).get('channels', []))

result = []
seen_conference_ids = set()
for ch_state in all_channels:
    ch   = ch_state.get('channel', {})
    msgs = list(ch_state.get('messages', []))

    extra_pages = 0
    while (len(msgs) == msg_limit * (extra_pages + 1)
           and local_date(msgs[0].get('created_at', '')) >= from_date):
        cid_parts = ch.get('cid', '').split(':', 1)
        if len(cid_parts) != 2:
            break
        older = fetch_older_messages(cid_parts[0], cid_parts[1], msgs[0]['id'])
        if not older:
            break
        msgs = older + msgs
        extra_pages += 1

    range_msgs = [
        m for m in msgs
        if from_date <= local_date(m.get('created_at', '')) <= to_date
        and m.get('type') != 'deleted'
    ]

    if not range_msgs:
        continue

    members = ch_state.get('members', [])
    other_names = [
        (m.get('user') or {}).get('name') or (m.get('user') or {}).get('id', '')
        for m in members if m.get('user') and (m.get('user') or {}).get('id') != my_user_id
    ]

    channel_name = (ch.get('name') or '').strip()
    if not channel_name:
        channel_name = ', '.join(other_names[:3]) or ch.get('cid', '')

    formatted_msgs = []
    for m in range_msgs:
        t = m.get('created_at', '')
        try:
            dt = datetime.fromisoformat(t.replace('Z', '+00:00')).astimezone()
            time_str = dt.strftime('%Y-%m-%d %H:%M') if from_date != to_date else dt.strftime('%H:%M')
        except:
            time_str = t[:16]

        text = m.get('text', '').strip()
        attachments = m.get('attachments', [])
        if not text and attachments:
            att_types = [a.get('type', 'file') for a in attachments]
            text = f"[{', '.join(att_types)}]"

        event_str = m.get('event', '')
        if event_str:
            try:
                event_data = json.loads(event_str)
                conf_id = (event_data.get('conference') or {}).get('id')
                if conf_id:
                    seen_conference_ids.add(conf_id)
            except Exception:
                pass

        sender = (m.get('user') or {}).get('name') or (m.get('user') or {}).get('id', '')
        formatted_msgs.append({'time': time_str, 'from': sender, 'text': text})

    result.append({
        'channelId': ch.get('cid', ''),
        'name': channel_name,
        'type': ch.get('type', ''),
        'messageCount': len(range_msgs),
        'messages': formatted_msgs,
    })

label = from_date if from_date == to_date else f"{from_date} to {to_date}"
print(json.dumps({
    'period': label,
    'timeZone': datetime.now().astimezone().strftime('UTC%z'),
    'userId': my_user_id,
    'totalChannels': len(result),
    'totalMessages': sum(c['messageCount'] for c in result),
    'conferenceIds': sorted(seen_conference_ids),
    'channels': result,
}, indent=2, ensure_ascii=False))
PYEOF
