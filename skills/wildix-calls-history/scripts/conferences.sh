#!/usr/bin/env bash
# Conferences: the record, the transcription, the AI insights, the recording.
# Usage: conferences.sh <command> <conference> [args]   (exact shapes: references/conferences.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: conferences.sh <command> <conference> [args]
  get <conf>                      the record: subject, times, participants, recordings, transcription status
  brief <conf>...                 one readable object per conference: record + participants + summary + insights;
                                  with several conferences: an array, oldest first (one that fails is skipped with a warning)
  transcript <conf> [--out FILE] [--json] [--structured]
                                  the dialogue as text with a header (exit 3 when there is none);
                                  --json: the text and its chunks as the service gives them;
                                  --structured: the raw transcription record with the interaction data
  annotations <conf>
  insights <conf> [--raw]         the AI insights that were generated (compact; --raw: as the service gives them)
  summary <conf>                  the AI title, brief and the structured summary
  state <conf>                    the viewer's own state: playlists, playback position
  timeframes <conf>               who spoke when
  recording-url --file-id ID --category channels|recordings|wizyconfRecordings [--download]
  schedule-summary <conf>         ask the service to (re)generate the summary
A conference is an id or a link https://app.x-bees.com/insights/conferences/<id>.
U
  exit 1; }

# brief_one ID: the readable card of one conference. Call it as  card=$(brief_one ID) || ...  and mind that
# bash ignores `set -e` inside a condition: every call that can fail is checked by hand.
brief_one() {
  id="$1"
  conf=$(wda_call GET "/history/conferences/$id") || return 1
  # a 404 (nothing generated) is silent; any other failure prints its error, and the card says "UNKNOWN"
  ins=$(WDA_SOFT=1 wda_call GET "/insights/conferences/$id/insights") || ins='{}'
  sum=$(WDA_SOFT=1 wda_call GET "/insights/conferences/$id/summary") || sum='{}'
  jq -c --argjson ins "$(jq -c "$compact_insights" <<<"$ins" 2>/dev/null || echo '{}')" --argjson sum "$sum" --arg id "$id" '.conference as $c | {
      id: $id,
      subject: $c.subject,
      start: (($c.startTime // 0) / 1000 | todate),
      durationMin: ((($c.duration // 0) / 60000) | round),
      status: $c.status,
      direction: $c.direction,
      participants: ([($c.participants // [])[] | (.info // {}) as $i | select(($i.name // $i.email) != null) | {name: ($i.name // $i.email), email: $i.email, xbsId: $i.xbsId, speak: (.totalSpeakDuration // 0)}] | group_by(.email // .name) | map(.[0] + {speakMin: ((map(.speak) | add) / 60000 | round)} | del(.speak))),
      transcriptionStatus: $c.transcriptionStatus,
      transcriptionLanguage: $c.transcriptionLanguage,
      hasRecording: (($c.recordings // []) | length > 0),
      summary: (if ($sum.status // "") == "SUCCEEDED" then {title: $sum.summary.title, brief: $sum.summary.brief,
          topics: ($sum.summary.json.topics // []), review: ($sum.summary.json.review // []), decisions: ($sum.summary.json.decisions // []), progress: ($sum.summary.json.progress // []),
          issues: ($sum.summary.json.issues // []), actionItems: ($sum.summary.json.actionItems // []), nextSteps: ($sum.summary.json.nextSteps // [])} else {status: ($sum.status // "UNKNOWN")} end),
      insights: $ins
    }' <<<"$conf"
}

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

# the insights that succeeded, as {projectionId: {fieldId: value}}
compact_insights='(.insights // []) | map(select(.status == "SUCCEEDED" and ((.fields // []) | length) > 0)) | map({(.id): ((.fields // []) | map({(.id): .value}) | add)}) | add // {}'

case "$cmd" in
  get)
    [[ $# -eq 1 ]] || usage
    wda_call GET "/history/conferences/$(norm_conference "$1")" ;;
  brief)
    [[ $# -ge 1 ]] || usage
    if [[ $# -eq 1 ]]; then
      brief_one "$(norm_conference "$1")"
    else
      cards=()
      for c in "$@"; do
        id=$(norm_conference "$c")
        card=$(brief_one "$id") || card=""
        if [[ -n "$card" ]]; then cards+=("$card"); else echo "Warning: skipped $id (see the error above)" >&2; fi
      done
      [[ ${#cards[@]} -gt 0 ]] || exit 1
      printf '%s\n' "${cards[@]}" | jq -cs 'sort_by(.start)'
    fi ;;
  transcript)
    [[ $# -ge 1 ]] || usage
    id=$(norm_conference "$1"); shift
    out=""; mode=text
    while [[ $# -gt 0 ]]; do case "$1" in
      --out) out="$2"; shift 2 ;; --json) mode=json; shift ;; --structured) mode=structured; shift ;; *) usage ;; esac; done
    if [[ $mode == structured ]]; then
      rc=0; r=$(WDA_SOFT=1 wda_call GET "/history/conferences/$id/transcription") || rc=$?
      if [[ $rc -eq 4 ]]; then echo "This conference has no transcription, or there is no such conference." >&2; exit 3; fi
      [[ $rc -eq 0 ]] || exit "$rc"
      printf '%s\n' "$r"; exit 0
    fi
    rc=0; r=$(WDA_SOFT=1 wda_call GET "/history/conferences/$id/transcription/text") || rc=$?
    if [[ $rc -eq 4 ]]; then echo "This conference has no transcription, or there is no such conference." >&2; exit 3; fi
    [[ $rc -eq 0 ]] || exit "$rc"
    if [[ $mode == json ]]; then printf '%s\n' "$r"; exit 0; fi
    text=$(jq -r '.text // ""' <<<"$r")
    [[ -n "${text//[[:space:]]/}" ]] || { echo "The transcription is empty: nothing was transcribed on this call." >&2; exit 3; }
    conf=$(wda_call GET "/history/conferences/$id")
    header=$(jq -r --arg id "$id" '.conference as $c | def one: gsub("[\\r\\n]+"; " "); [
        "# " + (($c.subject // "Conference") | one),
        "# conferenceId: " + $id,
        "# url: https://app.x-bees.com/insights/conferences/" + $id,
        "# start: " + (($c.startTime // 0) / 1000 | todate),
        "# duration: " + ((($c.duration // 0) / 60000) | round | tostring) + " min",
        "# language: " + ($c.transcriptionLanguage // "unknown"),
        "# participants: " + ([($c.participants // [])[] | (.info // {}) | (.name // .email)] | map(select(. != null) | one) | unique | join(", ")),
        ""] | join("\n")' <<<"$conf")
    if [[ -n "$out" ]]; then
      check_out_path "$out" "$id"
      ( umask 077; mkdir -p "$(dirname -- "$out")"; { printf '%s\n' "$header"; printf '%s\n' "$text"; } > "$out" )
      printf '%s\n' "$out"
    else
      printf '%s\n' "$header"; printf '%s\n' "$text"
    fi ;;
  annotations)
    [[ $# -eq 1 ]] || usage
    wda_call GET "/history/conferences/$(norm_conference "$1")/annotations" ;;
  insights)
    [[ $# -ge 1 ]] || usage
    id=$(norm_conference "$1"); shift; raw=0
    while [[ $# -gt 0 ]]; do case "$1" in --raw) raw=1; shift ;; *) usage ;; esac; done
    r=$(wda_call GET "/insights/conferences/$id/insights")
    if [[ $raw -eq 1 ]]; then printf '%s\n' "$r"; else jq -c "{status, insights: ($compact_insights)}" <<<"$r"; fi ;;
  summary)
    [[ $# -eq 1 ]] || usage
    wda_call GET "/insights/conferences/$(norm_conference "$1")/summary" ;;
  state)
    [[ $# -eq 1 ]] || usage
    wda_call GET "/insights/conferences/$(norm_conference "$1")/state" ;;
  timeframes)
    [[ $# -eq 1 ]] || usage
    wda_call GET "/insights/conferences/$(norm_conference "$1")/timeframes" ;;
  recording-url)
    fid=""; cat=""; dl=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --file-id) fid="$2"; shift 2 ;; --category) cat="$2"; shift 2 ;; --download) dl="1"; shift ;; *) usage ;; esac; done
    [[ -n "$fid" && -n "$cat" ]] || die "--file-id and --category are required"
    wda_call GET "/insights/conferences/recording/download_url$(qs fileId "$fid" category "$cat" download "$dl")" ;;
  schedule-summary)
    [[ $# -eq 1 ]] || usage
    wda_call POST "/insights/conferences/$(norm_conference "$1")/schedule_summary_generation" ;;
  *) usage ;;
esac
