#!/usr/bin/env bash
# Finding calls and meetings: the user's own call history, and the search over all conversations (calls,
# conferences, chats) with the AI summary of each.
# Usage: conversations.sh <command> [options]   (exact shapes: references/conversations.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: conversations.sh <command> [options]
  calls [--direction INTERNAL|INBOUND|OUTBOUND] [--status COMPLETED|MISSED] [--flag FAX|VOICEMAIL]...
        [--from ISO] [--to ISO] [--search TEXT] [--tag TAG]... [--has-attachment]
        [--user-direction INCOMING|OUTGOING] [--limit N] [--offset N] [--brief]
                                   the user's own call history, newest first
  find   [--entity call|conference|chat]... [--email E]... [--phone P]... [--extension X]... [--everyone]
         [--transcribed] [--recorded] [--direction inbound|outbound|internal]
         [--from ISO --to ISO [--tz ZONE]] [--when TODAY|YESTERDAY|THIS_WEEK|PREVIOUS_WEEK|THIS_MONTH|PREVIOUS_MONTH|THIS_QUARTER|LAST_30_DAYS]
         [--tag T]... [--language L]... [--cursor KEY] [--brief]
                                   the search over conversations with the summary of each (10 per page)
  count  (the same filters as find)
  tags <prefix> [--limit N]        tags that start with the prefix
find and count look only at conversations the logged-in user took part in, unless --everyone is given
(the service still decides what the login may see).
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

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
  if [[ "$parts" == '[]' && $everyone -eq 0 ]]; then parts=$(jq -nc --arg v "$(wildix_token_email)" '[{email:$v}]'); fi
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
  tags)
    [[ $# -ge 1 ]] || usage
    prefix="$1"; shift; limit=""
    while [[ $# -gt 0 ]]; do case "$1" in --limit) limit="$2"; shift 2 ;; *) usage ;; esac; done
    wda_call GET "/insights/conversations/tags$(qs tagPrefix "$prefix" limit "$limit")" ;;
  *) usage ;;
esac
