#!/bin/bash
# Usage: get-conference.sh <ID_TOKEN> <conferenceId> [conferenceId2 ...]
# Fetches conference details + insights from wda.wildix.com for one or more conference IDs.
# Returns a JSON array of enriched conference objects sorted by start time.
set -euo pipefail

ID_TOKEN="${1:?Usage: get-conference.sh <ID_TOKEN> <conferenceId> [...]}"
shift
if [ $# -eq 0 ]; then
  echo '[]'
  exit 0
fi

python3 - "$ID_TOKEN" "$@" <<'PYEOF'
import json, sys, urllib.request, concurrent.futures

id_token = sys.argv[1]
conf_ids = sys.argv[2:]

def get(url):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {id_token}", "User-Agent": "wildix-agent-skills/1.1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"  Warning: GET {url} failed: {e}", file=sys.stderr)
        return None

def fetch_conference_with_insights(conf_id):
    base = "https://wda.wildix.com/v2"
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        f_conf     = ex.submit(get, f"{base}/history/conferences/{conf_id}")
        f_insights = ex.submit(get, f"{base}/insights/conferences/{conf_id}/insights")
        conf_data     = f_conf.result()
        insights_data = f_insights.result()

    if not conf_data:
        return None
    conf = conf_data.get('conference', {})

    insights = {}
    for item in (insights_data or {}).get('insights', []):
        if item.get('status') != 'SUCCEEDED' or not item.get('fields'):
            continue
        insights[item['id']] = {f['id']: f['value'] for f in item['fields']}

    seen = set()
    participants = []
    for p in conf.get('participants', []):
        info = p.get('info') or {}
        name = info.get('name') or info.get('email', '')
        if name and name not in seen:
            seen.add(name)
            participants.append({
                'name': name,
                'email': info.get('email', ''),
                'xbsId': info.get('xbsId', ''),
                'speakDurationMs': p.get('totalSpeakDuration', 0),
            })

    return {
        'id': conf_id,
        'subject': conf.get('subject', ''),
        'startTime': conf.get('startTime', 0),
        'durationMs': conf.get('duration', 0),
        'status': conf.get('status', ''),
        'participants': participants,
        'transcriptionStatus': conf.get('transcriptionStatus', ''),
        'transcriptionLanguage': conf.get('transcriptionLanguage', ''),
        'hasRecording': len(conf.get('recordings', [])) > 0,
        'insights': insights,
    }

with concurrent.futures.ThreadPoolExecutor(max_workers=5) as ex:
    futures = [ex.submit(fetch_conference_with_insights, cid) for cid in conf_ids]
    results = [f.result() for f in futures if f.result() is not None]

results.sort(key=lambda c: c.get('startTime', 0))
print(json.dumps(results, indent=2, ensure_ascii=False))
PYEOF
