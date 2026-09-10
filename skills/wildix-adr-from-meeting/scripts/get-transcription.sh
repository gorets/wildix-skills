#!/bin/bash
# Usage: get-transcription.sh <ID_TOKEN> <conferenceId> [outFile]
#
# Downloads the full transcription of a Wildix/x-bees conference and writes it as plain text:
#
#   # <subject> / conferenceId / url / start / duration / language / participants
#   [MM:SS] Speaker Name: text
#
# The dialogue body comes verbatim from wda.wildix.com's own text export
# (GET /v2/history/conferences/<id>/transcription/text), which already resolves speaker
# names and formats timestamps — the same output as the "download transcription" button
# in x-bees. The header is assembled from the conference record.
#
# Exits 3 when the conference has no transcription (it was never enabled on the call).
set -euo pipefail

ID_TOKEN="${1:?Usage: get-transcription.sh <ID_TOKEN> <conferenceId> [outFile]}"
CONF_ID="${2:?Usage: get-transcription.sh <ID_TOKEN> <conferenceId> [outFile]}"
OUT_FILE="${3:-}"

python3 - "$ID_TOKEN" "$CONF_ID" "$OUT_FILE" <<'PYEOF'
import json, sys, os, urllib.request, urllib.error, concurrent.futures
from datetime import datetime, timezone, timedelta

id_token, conf_id, out_file = sys.argv[1], sys.argv[2], sys.argv[3]
BASE = "https://wda.wildix.com/v2"
TZ = timezone(timedelta(hours=3))  # UTC+3, the timezone the KB records meetings in


def get(url):
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {id_token}",
        "User-Agent": "wildix-agent-skills/1.1.0",
    })
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def fail(msg, code=1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
    f_conf = ex.submit(get, f"{BASE}/history/conferences/{conf_id}")
    f_text = ex.submit(get, f"{BASE}/history/conferences/{conf_id}/transcription/text")

    try:
        conf = f_conf.result().get("conference", {})
    except urllib.error.HTTPError as e:
        if e.code == 401:
            fail("token rejected by wda.wildix.com (HTTP 401) — re-authenticate via wildix-auth", 2)
        if e.code == 404:
            fail(f"conference {conf_id} not found or not accessible")
        fail(f"cannot fetch conference {conf_id} (HTTP {e.code})")
    except Exception as e:
        fail(f"cannot fetch conference {conf_id}: {e}")

    try:
        body = f_text.result()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            fail("this conference has no transcription — it was never enabled on the call.", 3)
        fail(f"cannot fetch transcription (HTTP {e.code})")
    except Exception as e:
        fail(f"cannot fetch transcription: {e}")

status = conf.get("transcriptionStatus", "")
if status and status not in ("AVAILABLE", "SUCCEEDED", "COMPLETED"):
    fail(f"transcription is not available for this conference (transcriptionStatus={status!r}). "
         "It was most likely never enabled on the call.", 3)

dialogue = (body.get("text") or "").strip()
if not dialogue:
    fail("transcription is empty — nothing was transcribed on this call.", 3)

names = sorted({
    (p.get("info") or {}).get("name") or (p.get("info") or {}).get("email")
    for p in conf.get("participants", [])
} - {None, ""})

start_dt = datetime.fromtimestamp((conf.get("startTime") or 0) / 1000, TZ)

header = "\n".join([
    f"# {(conf.get('subject') or 'Conference').strip()}",
    f"# conferenceId: {conf_id}",
    f"# url: https://app.x-bees.com/insights/conferences/{conf_id}",
    f"# start: {start_dt.strftime('%Y-%m-%dT%H:%M')} (UTC+3)",
    f"# duration: {round((conf.get('duration') or 0) / 60000)} min",
    f"# language: {conf.get('transcriptionLanguage') or 'unknown'}",
    f"# participants: {', '.join(names) or 'unknown'}",
    f"# lines: {len(body.get('chunks') or [])}",
    "",
])

out = header + dialogue + "\n"

if out_file:
    os.makedirs(os.path.dirname(os.path.abspath(out_file)), exist_ok=True)
    with open(out_file, "w", encoding="utf-8") as fh:
        fh.write(out)
    print(out_file)
else:
    sys.stdout.write(out)
PYEOF
