#!/usr/bin/env bash
# Calls: the record, the transcription, the AI insights. A call is a call id and a flow index (default 0).
# Usage: calls.sh <command> <callId> [flowIndex] [args]   (exact shapes: references/calls.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: calls.sh <command> <callId> [flowIndex] [args]
  get <callId> [flow]                  the record: who called whom, times, queue, trunk, recordings
  brief <callId> [flow]                one readable object: record + summary + insights state
  transcript <callId> [flow] [--out FILE] [--json] [--structured]
                                       the dialogue as text (exit 3 when there is none); --json: text and chunks;
                                       --structured: the raw transcription record
  annotations <callId> [flow]
  insights <callId> [flow] [--raw]     the AI insights that were generated
  summary <callId> [flow]
  characteristics <callId> [flow]      talk time, interruptions, sentiment, talk speed
  state <callId> [flow]                the viewer's own state: playlists, playback position
  schedule-summary <callId> [flow]     ask the service to (re)generate the summary
The flow index is 0 for the first part of the call; a transferred call has more flows.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift
[[ $# -ge 1 ]] || usage
call="$1"; shift
flow=0
if [[ $# -ge 1 && "$1" != --* ]]; then flow=$(norm_flow "$1"); shift; fi
base="/$call/flows/$flow"

compact_insights='(.insights // []) | map(select(.status == "SUCCEEDED" and ((.fields // []) | length) > 0)) | map({(.id): ((.fields // []) | map({(.id): .value}) | add)}) | add // {}'

case "$cmd" in
  get)
    wda_call GET "/history/calls$base" ;;
  brief)
    rec=$(wda_call GET "/history/calls$base")
    sum=$(WDA_SOFT=1 wda_call GET "/insights/calls$base/summary" 2>/dev/null) || sum='{}'
    ins=$(WDA_SOFT=1 wda_call GET "/insights/calls$base/insights" 2>/dev/null) || ins='{}'
    jq -c --argjson sum "$sum" --argjson ins "$(jq -c "$compact_insights" <<<"$ins" 2>/dev/null || echo '{}')" --arg id "$call" '.call as $c | {
        id: $id, flowIndex: $c.flowIndex,
        start: (($c.startTime // 0) / 1000 | todate),
        durationSec: (($c.duration // 0) / 1000 | round),
        talkSec: (($c.talkTime // 0) / 1000 | round),
        direction: $c.direction, status: $c.callStatus,
        caller: ($c.caller | {name, phone, extension: .userExtension, email}?), callee: ($c.callee | {name, phone, extension: .userExtension, email}?),
        queue: $c.queueName, service: $c.service, tags: ($c.tags // []),
        transcriptionStatus: $c.transcriptionStatus, hasRecording: ((($c.recordingsData // []) | length) > 0),
        summary: (if ($sum.status // "") == "SUCCEEDED" then {title: $sum.summary.title, brief: $sum.summary.brief} else {status: ($sum.status // "UNKNOWN")} end),
        insights: $ins
      }' <<<"$rec" ;;
  transcript)
    out=""; mode=text
    while [[ $# -gt 0 ]]; do case "$1" in
      --out) out="$2"; shift 2 ;; --json) mode=json; shift ;; --structured) mode=structured; shift ;; *) usage ;; esac; done
    if [[ $mode == structured ]]; then
      rc=0; r=$(WDA_SOFT=1 wda_call GET "/history/calls$base/transcription") || rc=$?
      if [[ $rc -eq 4 ]]; then echo "This call has no transcription, or there is no such call." >&2; exit 3; fi
      [[ $rc -eq 0 ]] || exit "$rc"
      printf '%s\n' "$r"; exit 0
    fi
    rc=0; r=$(WDA_SOFT=1 wda_call GET "/history/calls$base/transcription/text") || rc=$?
    if [[ $rc -eq 4 ]]; then echo "This call has no transcription, or there is no such call." >&2; exit 3; fi
    [[ $rc -eq 0 ]] || exit "$rc"
    if [[ $mode == json ]]; then printf '%s\n' "$r"; exit 0; fi
    text=$(jq -r '.text // ""' <<<"$r")
    [[ -n "${text//[[:space:]]/}" ]] || { echo "The transcription is empty." >&2; exit 3; }
    if [[ -n "$out" ]]; then mkdir -p "$(dirname "$out")"; printf '%s\n' "$text" > "$out"; printf '%s\n' "$out"; else printf '%s\n' "$text"; fi ;;
  annotations)
    wda_call GET "/history/calls$base/annotations" ;;
  insights)
    raw=0
    while [[ $# -gt 0 ]]; do case "$1" in --raw) raw=1; shift ;; *) usage ;; esac; done
    r=$(wda_call GET "/insights/calls$base/insights")
    if [[ $raw -eq 1 ]]; then printf '%s\n' "$r"; else jq -c "{status, insights: ($compact_insights)}" <<<"$r"; fi ;;
  summary)
    wda_call GET "/insights/calls$base/summary" ;;
  characteristics)
    wda_call GET "/insights/calls$base/characteristics" ;;
  state)
    wda_call GET "/insights/calls$base/state" ;;
  schedule-summary)
    wda_call POST "/insights/calls$base/schedule_summary_generation" ;;
  *) usage ;;
esac
