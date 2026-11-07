#!/usr/bin/env bash
# Finding calls and meetings: the user's own call history, and the search over all conversations (calls,
# conferences, chats) with the AI summary of each.
# Usage: conversations.sh <command> [options]   (exact shapes: references/conversations.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: conversations.sh <command> [options]
  calls [--direction INTERNAL|INBOUND|OUTBOUND] [--status COMPLETED|MISSED] [--flag FAX|VOICEMAIL]...
        [--from ISO] [--to ISO] [--search TEXT] [--tag TAG]... [--has-attachment]
        [--user-direction INCOMING|OUTGOING] [--limit 1-100] [--offset N] [--brief]
                                   the user's own call history, newest first, 50 per page by default
  find   [--entity call|conference|chat]... [--email E]... [--phone P]... [--extension X]... [--everyone]
         [--transcribed] [--recorded] [--direction inbound|outbound|internal]
         [--from ISO --to ISO [--tz ZONE]] [--when TODAY|YESTERDAY|THIS_WEEK|PREVIOUS_WEEK|THIS_MONTH|PREVIOUS_MONTH|THIS_QUARTER|LAST_30_DAYS]
         [--tag T]... [--language L]... [--cursor KEY] [--brief]
                                   the search over conversations with the summary of each (10 per page)
  count  (the same filters as find)
  aggregate --by DIM[,DIM...] [find filters] [--tz ZONE] [--top N] [--raw]
  aggregate --by DIM --then DIM [--then DIM] [find filters] [--tz ZONE] [--top N] [--raw]
  aggregate --projections [find filters]
                                   how many conversations fall into each value of a dimension (a chart's data):
                                   several dimensions side by side, or one broken down by others (--then).
                                   DIM: direction entity channel recorded language country location pbx trunk
                                   queue service extension group department tag chatbot voicebot duration
                                   connectTime talkTime waitTime queueTime holdTime date dayOfWeek hourOfDay
                                   projection:<id>:<field> (an AI insight field; --projections lists them).
                                   --tz: the zone of date, dayOfWeek and hourOfDay (the local one by default);
                                   --top: keep the N biggest values of each level
  tags <prefix> [--limit 1-20]     tags that start with the prefix
find and count look only at conversations the logged-in user took part in, unless --everyone is given
(the service still decides what the login may see).
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

AGG_DIMS=" direction entity channel recorded language country location pbx trunk queue service extension group department tag chatbot voicebot duration connectTime talkTime waitTime queueTime holdTime date dayOfWeek hourOfDay "

# The local IANA time zone, for the dimensions cut in a zone.
local_tz() {
  local z="${TZ:-}"
  [[ -n "$z" ]] || z=$(readlink /etc/localtime 2>/dev/null | sed -n 's#.*zoneinfo/##p')
  [[ -n "$z" ]] || z=$(cat /etc/timezone 2>/dev/null || true)
  printf '%s' "${z:-UTC}"
}

# agg_def DIM TZ -> the AggregationDefinition of one dimension.
agg_def() {
  local d="$1" tz="$2"
  if [[ "$d" == projection:* ]]; then
    local rest="${d#projection:}" id field
    id="${rest%%:*}"; field="${rest#*:}"
    [[ "$rest" == *:* && "$id" =~ ^[A-Za-z0-9_-]{1,100}$ && "$field" =~ ^[A-Za-z0-9_-]{1,100}$ ]] || die "a projection is projection:<id>:<field>: $d"
    jq -nc --arg i "$id" --arg f "$field" '{projection:{id:$i, fieldId:$f}}'
  elif [[ "$AGG_DIMS" == *" $d "* ]]; then
    case "$d" in
      date|dayOfWeek|hourOfDay) jq -nc --arg d "$d" --arg z "$tz" '{($d):{timeZone:$z}}' ;;
      *) jq -nc --arg d "$d" '{($d):{}}' ;;
    esac
  else die "not a dimension: $d (run the script without arguments for the list)"; fi
}

# The ListConversations filter from the common options; sets FILTER and CURSOR, BRIEF.
build_filter() {
  FILTER='{}'; CURSOR=""; BRIEF=0
  local entities=() emails=() phones=() exts=() tags=() langs=() everyone=0
  local transcribed=0 recorded=0 direction="" from="" to="" tz="" when=""
  while [[ $# -gt 0 ]]; do case "$1" in
    --entity) entities+=("$2"); shift 2 ;;
    --email) emails+=("$2"); shift 2 ;; --phone) phones+=("$2"); shift 2 ;; --extension) exts+=("$2"); shift 2 ;;
    --everyone) everyone=1; shift ;;
    --transcribed) transcribed=1; shift ;; --recorded) recorded=1; shift ;;
    --direction) direction="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;; --to) to="$2"; shift 2 ;; --tz) tz="$2"; shift 2 ;; --when) when="$2"; shift 2 ;;
    --tag) tags+=("$2"); shift 2 ;; --language) langs+=("$2"); shift 2 ;;
    --cursor) CURSOR="$2"; shift 2 ;; --brief) BRIEF=1; shift ;;
    *) usage ;; esac; done

  if [[ ${#entities[@]} -gt 0 ]]; then
    local e='{}'
    for x in "${entities[@]}"; do
      [[ "$x" == call || "$x" == conference || "$x" == chat ]] || die "--entity is call, conference or chat: $x"
      jsetj e "$x" true
    done
    jsetj FILTER entity "$e"
  fi

  local parts='[]'
  for x in ${emails[@]+"${emails[@]}"}; do parts=$(jq -c --arg v "$x" '. + [{email:$v}]' <<<"$parts"); done
  for x in ${phones[@]+"${phones[@]}"}; do parts=$(jq -c --arg v "$x" '. + [{phone:$v}]' <<<"$parts"); done
  for x in ${exts[@]+"${exts[@]}"}; do parts=$(jq -c --arg v "$x" '. + [{extension:$v}]' <<<"$parts"); done
  if [[ "$parts" == '[]' && $everyone -eq 0 ]]; then
    local me; me=$(wildix_token_email); [[ -n "$me" ]] || die "the token carries no e-mail"
    parts=$(jq -nc --arg v "$me" '[{email:$v}]')
  fi
  [[ "$parts" == '[]' ]] || jsetj FILTER participants "$parts"

  [[ $transcribed -eq 0 ]] || jsetj FILTER transcribed true
  [[ $recorded -eq 0 ]] || jsetj FILTER recorded true
  if [[ -n "$direction" ]]; then
    case "$direction" in inbound|outbound|internal) jsetj FILTER direction "$(jq -nc --arg d "$direction" '{($d): true}')" ;; *) die "--direction is inbound, outbound or internal: $direction" ;; esac
  fi
  if [[ -n "$when" ]]; then
    jsetj FILTER date "$(jq -nc --arg t "$when" --arg z "$tz" '{predefined: ({type:$t} + (if $z != "" then {timeZone:$z} else {} end))}')"
  elif [[ -n "$from" || -n "$to" ]]; then
    jsetj FILTER date "$(jq -nc --arg f "$from" --arg t "$to" --arg z "$tz" '{absolute: ((if $f != "" then {from:$f} else {} end) + (if $t != "" then {to:$t} else {} end) + (if $z != "" then {timeZone:$z} else {} end))}')"
  fi
  if [[ ${#tags[@]} -gt 0 ]]; then jsetj FILTER tag "$(jarr "${tags[@]}")"; fi
  if [[ ${#langs[@]} -gt 0 ]]; then jsetj FILTER language "$(jarr "${langs[@]}")"; fi
}

case "$cmd" in
  calls)
    direction=""; status=""; flags=(); from=""; to=""; search=""; tags=(); att=0; udir=""; limit=""; offset=""; brief=0
    while [[ $# -gt 0 ]]; do case "$1" in
      --direction) direction="$2"; shift 2 ;; --status) status="$2"; shift 2 ;; --flag) flags+=("$2"); shift 2 ;;
      --from) from="$2"; shift 2 ;; --to) to="$2"; shift 2 ;; --search) search="$2"; shift 2 ;; --tag) tags+=("$2"); shift 2 ;;
      --has-attachment) att=1; shift ;; --user-direction) udir="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;; --offset) offset="$2"; shift 2 ;; --brief) brief=1; shift ;; *) usage ;; esac; done
    [[ -z "$limit" ]] || check_int --limit "$limit" 1 100
    [[ -z "$offset" ]] || check_int --offset "$offset" 0 1000000
    f='{}'
    [[ -z "$direction" ]] || jset f direction "$direction"
    [[ -z "$status" ]] || jset f status "$status"
    if [[ ${#flags[@]} -gt 0 ]]; then jsetj f flags "$(jarr "${flags[@]}")"; fi
    [[ -z "$from" ]] || jset f from "$from"
    [[ -z "$to" ]] || jset f to "$to"
    [[ -z "$search" ]] || jset f search "$search"
    if [[ ${#tags[@]} -gt 0 ]]; then jsetj f tags "$(jarr "${tags[@]}")"; fi
    [[ $att -eq 0 ]] || jsetj f hasAttachment true
    [[ -z "$udir" ]] || jset f userDirection "$udir"
    body=$(jq -nc --argjson f "$f" '{filter:$f}')
    [[ -z "$limit" ]] || jsetj body limit "$limit"
    [[ -z "$offset" ]] || jsetj body offset "$offset"
    r=$(wda_call POST /history/user/calls "$body")
    if [[ $brief -eq 1 ]]; then
      jq -c '{calls: [.calls[] | {id, flowIndex, start: ((.startTime // 0) / 1000 | todate), durationSec: (((.duration // 0) / 1000) | round), direction, status: .callStatus,
          from: (.caller.name // .caller.phone // .caller.userExtension), to: (.callee.name // .callee.phone // .callee.userExtension),
          transcriptionStatus, hasRecording: (((.recordingsData // []) | length) > 0)}]}' <<<"$r"
    else printf '%s\n' "$r"; fi ;;
  find)
    build_filter "$@"
    body=$(jq -nc --argjson f "$FILTER" '{filter:$f}')
    [[ -z "$CURSOR" ]] || jset body exclusiveStartKey "$CURSOR"
    r=$(wda_call POST /insights/conversations "$body")
    if [[ $BRIEF -eq 1 ]]; then
      jq -c '{items: [.items[] | (.event | to_entries[0]) as $e | $e.value as $v | {
            type: $e.key,
            id: ($v.id // $v.chatId),
            flowIndex: $v.flowIndex,
            start: (($v.startTime // 0) / 1000 | todate),
            durationSec: ((($v.duration // 0) / 1000) | round),
            title: ($v.subject // null),
            direction: $v.direction,
            status: ($v.status // $v.callStatus),
            participants: (if $e.key == "conference" then [($v.participants // [])[] | (.info // {}) | (.name // .email)] | map(select(. != null)) | unique else null end),
            summary: (.summary | {status, title, brief})
          }], nextCursor: .lastEvaluatedKey}' <<<"$r"
    else printf '%s\n' "$r"; fi ;;
  count)
    build_filter "$@"
    wda_call POST /insights/conversations/count "$(jq -nc --argjson f "$FILTER" '{filter:$f}')" ;;
  aggregate)
    by=""; thens=(); tz=""; top=""; raw=0; projections=0; rest=()
    while [[ $# -gt 0 ]]; do case "$1" in
      --by) [[ $# -ge 2 ]] || usage; by="$2"; shift 2 ;;
      --then) [[ $# -ge 2 ]] || usage; thens+=("$2"); shift 2 ;;
      --tz) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^[A-Za-z][A-Za-z0-9_+/-]{0,63}$ ]] || die "not a time zone: $2"; tz="$2"; rest+=(--tz "$2"); shift 2 ;;
      --top) [[ $# -ge 2 ]] || usage; check_int --top "$2" 1 1000; top=$((10#$2)); shift 2 ;;
      --raw) raw=1; shift ;;
      --projections) projections=1; shift ;;
      *) rest+=("$1"); shift ;; esac; done
    build_filter ${rest[@]+"${rest[@]}"}
    [[ -n "$tz" ]] || tz=$(local_tz)
    # Buckets without their drill-down filters (each bucket repeats the whole filter), weekdays named, the hours
    # and weekdays in order, nested levels named by their dimension.
    shape='
      def dim: (keys[0]) as $k | if $k == "projection" then "projection:\(.projection.id):\(.projection.fieldId)" else $k end;
      def wd: ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
      def level($r):
        ($r.aggregation | dim) as $d
        | {by: $d, buckets: (
            ($r.buckets // [])
            | (if $d == "hourOfDay" or $d == "dayOfWeek" then sort_by(.key | tonumber) else . end)
            | (if $top != null and $d != "hourOfDay" and $d != "dayOfWeek" and $d != "date" then sort_by(-.count) | .[:$top] else . end)
            | map({key, count}
                + (if $d == "dayOfWeek" then {day: wd[(.key | tonumber)]} else {} end)
                + (if .interval then {interval} else {} end)
                + (if .aggregation then {then: level(.aggregation)} else {} end)))};'
    if [[ $projections -eq 1 ]]; then
      r=$(wda_call POST /insights/conversations/aggregations "$(jq -nc --argjson f "$FILTER" '{filter:$f}')")
      jq -c '{count, projections: [.result[] | select(.aggregation.projection) | select((.buckets | length) > 0)
          | {by: "projection:\(.aggregation.projection.id):\(.aggregation.projection.fieldId)", values: (.buckets | map(.count) | add), top: (.buckets | sort_by(-.count) | .[:5] | map({key, count}))}]}' <<<"$r"
      exit 0
    fi
    [[ -n "$by" ]] || die "aggregate needs --by (or --projections)"
    defs='[]'
    IFS=',' read -r -a bys <<<"$by"
    if [[ ${#thens[@]} -gt 0 ]]; then
      [[ ${#bys[@]} -eq 1 ]] || die "with --then, --by names one dimension"
      [[ ${#thens[@]} -le 2 ]] || die "at most two --then"
      for d in "${bys[0]}" "${thens[@]}"; do x=$(agg_def "$d" "$tz") || exit 1; defs=$(jq -c --argjson x "$x" '. + [$x]' <<<"$defs"); done
      r=$(wda_call POST /insights/conversations/aggregations/nested "$(jq -nc --argjson f "$FILTER" --argjson a "$defs" '{filter:$f, aggregations:$a}')")
      if [[ $raw -eq 1 ]]; then printf '%s\n' "$r"; exit 0; fi
      jq -c --argjson top "${top:-null}" "$shape"' {count, timeZone: $tz} + level(.result)' --arg tz "$tz" <<<"$r"
    else
      [[ ${#bys[@]} -le 10 ]] || die "at most 10 dimensions side by side"
      for d in "${bys[@]}"; do x=$(agg_def "$d" "$tz") || exit 1; defs=$(jq -c --argjson x "$x" '. + [$x]' <<<"$defs"); done
      r=$(wda_call POST /insights/conversations/aggregations "$(jq -nc --argjson f "$FILTER" --argjson a "$defs" '{filter:$f, insights:$a}')")
      if [[ $raw -eq 1 ]]; then printf '%s\n' "$r"; exit 0; fi
      jq -c --argjson top "${top:-null}" "$shape"' {count, timeZone: $tz, results: [.result[] | level(.)]}' --arg tz "$tz" <<<"$r"
    fi ;;
  tags)
    [[ $# -ge 1 ]] || usage
    prefix="$1"; shift; limit=""
    while [[ $# -gt 0 ]]; do case "$1" in --limit) limit="$2"; shift 2 ;; *) usage ;; esac; done
    [[ -z "$limit" ]] || check_int --limit "$limit" 1 20
    wda_call GET "/insights/conversations/tags$(qs tagPrefix "$prefix" limit "$limit")" ;;
  *) usage ;;
esac
