#!/bin/bash
# Usage: ID_TOKEN=<token> get-unread.sh
set -euo pipefail

ID_TOKEN="${ID_TOKEN:?ID_TOKEN env var required. Usage: ID_TOKEN=<token> get-unread.sh}"

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

curl -sf \
  -H "User-Agent: wildix-agent-skills/1.1.0" \
  -H "Authorization: $STREAM_TOKEN" \
  -H "Stream-Auth-Type: jwt" \
  "$STREAM_DOMAIN/unread?api_key=$STREAM_API_KEY" > "$WORK/unread.json"

TOTAL=$(jq '.total_unread_count' "$WORK/unread.json")
if [ "$TOTAL" -eq 0 ]; then
  echo '{"total_unread_count": 0, "channels": []}'
  exit 0
fi

python3 - "$WORK" "$STREAM_TOKEN" "$STREAM_API_KEY" "$STREAM_DOMAIN" <<'PYEOF'
import json, sys, os, urllib.request

workdir        = sys.argv[1]
stream_token   = sys.argv[2]
stream_api_key = sys.argv[3]
stream_domain  = sys.argv[4]

with open(os.path.join(workdir, "unread.json")) as f:
    unread = json.load(f)

cids = [u['channel_id'] for u in unread.get('channels', [])]

def fetch_channels_batch(cid_batch):
    url  = f"{stream_domain}/channels?api_key={stream_api_key}"
    body = json.dumps({
        "filter_conditions": {"cid": {"$in": cid_batch}},
        "limit": len(cid_batch),
    }).encode()
    req = urllib.request.Request(url, data=body, headers={
        "Authorization": stream_token,
        "Stream-Auth-Type": "jwt",
        "User-Agent": "wildix-agent-skills/1.1.0",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read()).get('channels', [])

BATCH = 30
all_ch_states = []
for i in range(0, len(cids), BATCH):
    all_ch_states.extend(fetch_channels_batch(cids[i:i + BATCH]))

unread_by_cid = {u['channel_id']: u for u in unread.get('channels', [])}

result = []
for ch_state in all_ch_states:
    ch  = ch_state.get('channel', {})
    cid = ch.get('cid', '')
    unread_info = unread_by_cid.get(cid, {})

    members = ch_state.get('members', [])
    member_names = [
        (m.get('user') or {}).get('name') or (m.get('user') or {}).get('id', '')
        for m in members if m.get('user')
    ]

    msgs   = ch_state.get('messages', [])
    recent = [
        {
            'text': m.get('text', ''),
            'from': (m.get('user') or {}).get('name') or (m.get('user') or {}).get('id', ''),
            'createdAt': m.get('created_at', ''),
        }
        for m in msgs[-5:]
    ]

    result.append({
        'channelId': cid,
        'name': ch.get('name') or (', '.join(member_names[:3]) if len(members) <= 3 else f'Group ({len(members)})'),
        'channelType': ch.get('type', ''),
        'unreadCount': unread_info.get('unread_count', 0),
        'lastRead': unread_info.get('last_read', ''),
        'recentMessages': recent,
    })

result.sort(key=lambda x: -x['unreadCount'])

print(json.dumps({
    'total_unread_count': unread.get('total_unread_count', 0),
    'total_unread_threads': unread.get('total_unread_threads_count', 0),
    'channels': result,
}, indent=2, ensure_ascii=False))
PYEOF
