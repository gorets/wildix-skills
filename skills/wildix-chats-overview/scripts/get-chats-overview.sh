#!/bin/bash
# Usage: ID_TOKEN=<token> get-chats-overview.sh [from_date] [to_date]
#   from_date: YYYY-MM-DD, default = today
#   to_date:   YYYY-MM-DD, default = from_date (single day)
set -euo pipefail

ID_TOKEN="${ID_TOKEN:?ID_TOKEN env var required. Usage: ID_TOKEN=<token> get-chats-overview.sh [from_date] [to_date]}"
FROM_DATE="${1:-$(date +%Y-%m-%d)}"
TO_DATE="${2:-$FROM_DATE}"

XBEES_URL="https://api.x-bees.com"
STREAM_API_KEY="9p6289m44jum"
STREAM_DOMAIN="https://chat.wildix-chat.com"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

curl -sf \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H "Authorization: Bearer $ID_TOKEN" \
  "$XBEES_URL/v2/conversations/token?clientId=$STREAM_API_KEY" > "$WORK/stream_token.json"

STREAM_TOKEN=$(jq -r '.token' "$WORK/stream_token.json")
if [ -z "$STREAM_TOKEN" ] || [ "$STREAM_TOKEN" = "null" ]; then
  echo '{"error": "Failed to get Stream token"}' >&2
  exit 1
fi

USER_ID=$(jq -R 'split(".") | .[1] | @base64d | fromjson | .user_id' <<< "$STREAM_TOKEN" | tr -d '"')

PAGE_SIZE=30
MSG_LIMIT=100
OFFSET=0
PAGE_NUM=0

echo "Fetching channels..." >&2

while true; do
  PAGE_FILE="$WORK/channels_${PAGE_NUM}.json"
  curl -sf -X POST \
    -H "User-Agent: wildix-agent-skills/1.1.0" \
    -H "Authorization: $STREAM_TOKEN" \
    -H "Stream-Auth-Type: jwt" \
    -H "Content-Type: application/json" \
    -d "{
      \"filter_conditions\": {\"members\": {\"\$in\": [\"$USER_ID\"]}},
      \"sort\": [{\"field\": \"last_message_at\", \"direction\": -1}],
      \"limit\": $PAGE_SIZE,
      \"offset\": $OFFSET,
      \"message_limit\": $MSG_LIMIT
    }" \
    "$STREAM_DOMAIN/channels?api_key=$STREAM_API_KEY" > "$PAGE_FILE"

  COUNT=$(jq '.channels | length' "$PAGE_FILE")
  echo "  Page $PAGE_NUM: got $COUNT channels (offset=$OFFSET)" >&2

  PAGE_NUM=$((PAGE_NUM + 1))
  OFFSET=$((OFFSET + PAGE_SIZE))

  if [ "$COUNT" -lt "$PAGE_SIZE" ]; then
    break
  fi

  OLDEST_LAST_MSG=$(jq -r '[.channels[].channel.last_message_at // ""] | map(select(. != "")) | min' "$PAGE_FILE")
  if [ -n "$OLDEST_LAST_MSG" ] && [ "${OLDEST_LAST_MSG:0:10}" \< "$FROM_DATE" ]; then
    echo "  Early stop: oldest last_message_at=${OLDEST_LAST_MSG:0:10} is before $FROM_DATE" >&2
    break
  fi
done

python3 - "$WORK" "$USER_ID" "$FROM_DATE" "$TO_DATE" "$PAGE_NUM" "$STREAM_TOKEN" "$STREAM_API_KEY" "$STREAM_DOMAIN" "$MSG_LIMIT" <<'PYEOF'
import json, sys, os, urllib.request
from datetime import datetime, timezone

workdir    = sys.argv[1]
my_user_id = sys.argv[2]
from_date  = sys.argv[3]
to_date    = sys.argv[4]
num_pages  = int(sys.argv[5])
stream_token    = sys.argv[6]
stream_api_key  = sys.argv[7]
stream_domain   = sys.argv[8]
msg_limit       = int(sys.argv[9])

def fetch_older_messages(ch_type, ch_id, id_lt):
    url = f"{stream_domain}/channels/{ch_type}/{ch_id}/query?api_key={stream_api_key}"
    body = json.dumps({"state": True, "watch": False, "messages": {"limit": msg_limit, "id_lt": id_lt}}).encode()
    req = urllib.request.Request(url, data=body, headers={
        "Authorization": stream_token,
        "Stream-Auth-Type": "jwt",
        "User-Agent": "wildix-agent-skills/1.1.0",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req) as resp:
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
           and msgs[0].get('created_at', '')[:10] >= from_date):
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
        if from_date <= m.get('created_at', '')[:10] <= to_date
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
            dt = datetime.fromisoformat(t.replace('Z', '+00:00'))
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
    'totalChannels': len(result),
    'totalMessages': sum(c['messageCount'] for c in result),
    'conferenceIds': sorted(seen_conference_ids),
    'channels': result,
}, indent=2, ensure_ascii=False))
PYEOF
