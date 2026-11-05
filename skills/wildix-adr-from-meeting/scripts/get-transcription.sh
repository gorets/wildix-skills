#!/bin/bash
# Usage: get-transcription.sh <conferenceId> [outFile]
#
# The token is loaded by the wildix-auth skill and passed through the environment, never through argv:
# command-line arguments are visible to every process on the host (`ps`) and land in shell history.
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

USAGE='usage: get-transcription.sh <conferenceId> [outFile]'
CONF_ID="${1:?$USAGE}"
OUT_FILE="${2:-}"

# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
for _d in "$(dirname "$0")/../.." "${WILDIX_SKILLS_DIR:-}" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2

ID_TOKEN="$ID_TOKEN" python3 - "$CONF_ID" "$OUT_FILE" <<'PYEOF'
import json, re, sys, os, urllib.request, urllib.error, concurrent.futures
from datetime import datetime, timezone, timedelta

id_token = os.environ["ID_TOKEN"]
conf_id, out_file = sys.argv[1], sys.argv[2]
BASE = "https://wda.wildix.com/v2"
TZ = timezone.utc  # the header says UTC; whoever reads the file converts to their own zone


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


def one_line(text):
    """A value of the header must stay on one line: a subject with a newline must not add lines to the file."""
    return " ".join(str(text).split())


# a link or an id: drop ?query and #fragment and a trailing slash, take the last segment, accept id characters only
_raw_id = conf_id
conf_id = re.split(r"[?#]", _raw_id)[0].rstrip("/").rsplit("/", 1)[-1]
if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", conf_id) or ".." in conf_id or conf_id == "conferences":
    fail(f"not a conference id: {_raw_id}")


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
if status == "UNAVAILABLE":
    fail("transcription is not available for this conference (transcriptionStatus='UNAVAILABLE'). "
         "It was most likely never enabled on the call.", 3)

dialogue = (body.get("text") or "").strip()
if not dialogue:
    if status == "POST_TRANSCRIPTION":
        fail("the transcription is still being processed (transcriptionStatus='POST_TRANSCRIPTION'): try again later.", 3)
    fail("transcription is empty — nothing was transcribed on this call.", 3)

names = sorted({
    one_line((p.get("info") or {}).get("name") or (p.get("info") or {}).get("email") or "")
    for p in conf.get("participants", [])
} - {""})

start_dt = datetime.fromtimestamp((conf.get("startTime") or 0) / 1000, TZ)

header = "\n".join([
    f"# {one_line(conf.get('subject') or 'Conference')}",
    f"# conferenceId: {conf_id}",
    f"# url: https://app.x-bees.com/insights/conferences/{conf_id}",
    f"# start: {start_dt.strftime('%Y-%m-%dT%H:%M')} (UTC)",
    f"# duration: {round((conf.get('duration') or 0) / 60000)} min",
    f"# language: {conf.get('transcriptionLanguage') or 'unknown'}",
    f"# participants: {', '.join(names) or 'unknown'}",
    f"# lines: {len(body.get('chunks') or [])}",
    "",
])

out = header + dialogue + "\n"

if out_file:
    # an existing file is replaced only when it is the transcript of this very conference, written earlier by
    # this script (its second line says so): the path may have come from fetched text, so nothing else is touched
    if os.path.exists(out_file):
        try:
            with open(out_file, encoding="utf-8", errors="replace") as fh:
                second = fh.read(8192).split("\n")[1:2]
        except OSError:
            second = []
        if second != [f"# conferenceId: {conf_id}"]:
            fail(f"{out_file} exists: choose another path (nothing was overwritten)")
    os.umask(0o077)  # a transcript is confidential: private file, private folder
    os.makedirs(os.path.dirname(os.path.abspath(out_file)), exist_ok=True)
    with open(out_file, "w", encoding="utf-8") as fh:
        fh.write(out)
    print(out_file)
else:
    sys.stdout.write(out)
PYEOF
