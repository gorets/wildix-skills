#!/usr/bin/env bash
# Queues (call groups, services): reports on their calls over days, from the WDA x-caracal service, and the list
# of the queues of the company. Read only. Counts, never percentages: the rates are computed from the counts.
# Usage: queues.sh <command> [filter options]   (exact shapes: references/queues.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: queues.sh <command> [options]
  list [--name TEXT] [--pbx SERIAL]     the queues of the company: id, name, PBX (and how many on each PBX)
  summary                               every call of the filter: offered, answered, abandoned, lost, waits,
                                        talk, ring, deepest place in line, the SLA counts
  by-queue                              the same figures per queue
  by-period --by hour|day|week|month|weekday
                                        the same figures as a series (hour: the 24 hours of the day over the window)
  answered [--by queue|agent|user|reason|talk-time] [--band S --steps N]
                                        the answered calls: summary, or grouped (agent: a person in one queue;
                                        user: a person over every queue; talk-time: bands of S seconds)
  unanswered [--by queue|reason]        the abandoned and unanswered calls: summary (lost, overflow), or grouped
  service-level answered|unanswered [--band S] [--steps N]
                                        how many calls were answered (or given up) within 20, 40, … seconds
  calls [--limit N] [--pages N] [--cursor C] [--call CALLID]
                                        the calls one by one, newest first: queue, times, wait, talk, outcome,
                                        who answered, the caller; 50 a page, up to 200; --pages: follow the
                                        next pages (up to 20); --call: every queue a phone call went through
  events <callId> <flowIndex> [--queue ID]
                                        one call in one queue: its row and its events (INIT, RING, CANCEL, ANSWER,
                                        END) with the agents rung
Filter (every report command and calls):
  --from YYYY-MM-DD [--to YYYY-MM-DD]   the days, inclusive (today when both are left out; --to defaults to today)
  --days N                              the last N days, today included
  --tz ZONE                             the zone the days are cut in (the PBX's own by default)
  --pbx SERIAL                          the PBX (a report covers one; by default the PBX of the queue named, else
                                        the PBX of the login): `list` shows the PBXs that have queues
  --queue ID...                         only these queues (ids from `list`)
  --extension EXT...                    only the calls these users answered, or that rang them unanswered
  --outcome O...                        offered|received|answered|completed|transferred|abandoned|unanswered|
                                        lost|lostAbandoned|lostUnanswered|overflow|unknown
  --hours HH:MM-HH:MM                   time of day the call entered the queue (slow: reads every call)
  --weekday N...                        1 = Monday … 7 = Sunday (slow)
  --wait FROM-TO | --talk FROM-TO       a band of seconds: more than FROM, at most TO (TO may be left out) (slow)
  --reason R...                         disconnect reasons: HANGUP, TRANSFER, TIMEOUT, EMPTY, EXITWITHKEY, … (slow)
  --sla S                               the SLA threshold, 5 to 120 in steps of 5 (20 by default)
  --queue-sla ID=S...                   the threshold of one queue
Windows are at most 90 days; calls are kept about 3 months; figures lag the calls by about a minute.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

local_day() { jq -rn --argjson d "$1" '(now - $d * 86400) | strflocaltime("%Y-%m-%d")'; }
check_day() { [[ "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "$1 must be a day as YYYY-MM-DD: $2"; }
check_band() { [[ "$2" =~ ^[0-9]{1,5}-([0-9]{1,5})?$ ]] || die "$1 is a band of seconds as FROM-TO or FROM-: $2"; }
band_json() { local f="${1%-*}" t="${1#*-}"; if [[ -n "$t" ]]; then jq -cn --argjson f "$((10#$f))" --argjson t "$((10#$t))" '{from:$f,to:$t}'; else jq -cn --argjson f "$((10#$f))" '{from:$f}'; fi; }

from=""; to=""; days=""; tz=""; pbx=""; hours=""; wait_band=""; talk_band=""; sla=""
queues=(); exts=(); outcomes=(); weekdays=(); reasons=(); queue_slas=()
by=""; band=""; steps=""; limit=""; pages=1; cursor=""; call_id=""; name=""; positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) [[ $# -ge 2 ]] || usage; check_day --from "$2"; from="$2"; shift 2 ;;
    --to) [[ $# -ge 2 ]] || usage; check_day --to "$2"; to="$2"; shift 2 ;;
    --days) [[ $# -ge 2 ]] || usage; check_int --days "$2" 1 90; days=$((10#$2)); shift 2 ;;
    --tz) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^[A-Za-z][A-Za-z0-9_+/-]{0,63}$ ]] || die "not a time zone: $2"; tz="$2"; shift 2 ;;
    --pbx) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^[A-Za-z0-9]{4,32}$ ]] || die "not a PBX serial: $2"; pbx="$2"; shift 2 ;;
    --queue) [[ $# -ge 2 ]] || usage; check_id "the queue id" "$2"; queues+=("$2"); shift 2 ;;
    --extension) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^[0-9]{1,15}$ ]] || die "an extension is digits only: $2"; exts+=("$2"); shift 2 ;;
    --outcome) [[ $# -ge 2 ]] || usage
      [[ "$2" =~ ^(offered|received|answered|completed|transferred|abandoned|unanswered|lost|lostAbandoned|lostUnanswered|overflow|unknown)$ ]] || die "not an outcome: $2"
      outcomes+=("$2"); shift 2 ;;
    --hours) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^(([01][0-9]|2[0-3]):[0-5][0-9])-(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$ ]] || die "--hours is HH:MM-HH:MM: $2"; hours="$2"; shift 2 ;;
    --weekday) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^[1-7]$ ]] || die "--weekday is 1 (Monday) to 7 (Sunday): $2"; weekdays+=("$2"); shift 2 ;;
    --wait) [[ $# -ge 2 ]] || usage; check_band --wait "$2"; wait_band="$2"; shift 2 ;;
    --talk) [[ $# -ge 2 ]] || usage; check_band --talk "$2"; talk_band="$2"; shift 2 ;;
    --reason) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^[A-Za-z_]{0,40}$ ]] || die "not a disconnect reason: $2"; reasons+=("$2"); shift 2 ;;
    --sla) [[ $# -ge 2 ]] || usage; check_int --sla "$2" 5 120; (( 10#$2 % 5 == 0 )) || die "--sla is a multiple of 5: $2"; sla=$((10#$2)); shift 2 ;;
    --queue-sla) [[ $# -ge 2 ]] || usage; [[ "$2" =~ ^([A-Za-z0-9_+][A-Za-z0-9_.:+-]*)=([0-9]{1,3})$ ]] || die "--queue-sla is QUEUE_ID=SECONDS: $2"
      s="${BASH_REMATCH[2]}"; check_int "the SLA of a queue" "$s" 5 120; (( 10#$s % 5 == 0 )) || die "an SLA is a multiple of 5: $2"
      queue_slas+=("$2"); shift 2 ;;
    --by) [[ $# -ge 2 ]] || usage; by="$2"; shift 2 ;;
    --band) [[ $# -ge 2 ]] || usage; check_int --band "$2" 1 3600; band=$((10#$2)); shift 2 ;;
    --steps) [[ $# -ge 2 ]] || usage; check_int --steps "$2" 1 60; steps=$((10#$2)); shift 2 ;;
    --limit) [[ $# -ge 2 ]] || usage; check_int --limit "$2" 1 200; limit=$((10#$2)); shift 2 ;;
    --pages) [[ $# -ge 2 ]] || usage; check_int --pages "$2" 1 20; pages=$((10#$2)); shift 2 ;;
    --cursor) [[ $# -ge 2 ]] || usage; [[ ${#2} -le 2048 && "$2" =~ ^[A-Za-z0-9_=+/.:-]+$ ]] || die "not a cursor"; cursor="$2"; shift 2 ;;
    --call) [[ $# -ge 2 ]] || usage; check_id "the call id" "$2"; call_id="$2"; shift 2 ;;
    --name) [[ $# -ge 2 ]] || usage; [[ ${#2} -le 100 ]] || die "--name is too long"; name="$2"; shift 2 ;;
    -h|--help) usage ;;
    --*) usage ;;
    *) positional+=("$1"); shift ;;
  esac
done

# The filter of a report. A report covers one PBX: the one named, else the PBX of the first queue named (its id
# is <company>_<pbx>_<number>), else the PBX of the login (the service's default).
filter() {
  local f d1 d2
  if [[ -n "$days" ]]; then d1=$(local_day $((days - 1))); d2=$(local_day 0)
  else d2="${to:-$(local_day 0)}"; d1="${from:-$d2}"; fi
  [[ "$d1" < "$d2" || "$d1" == "$d2" ]] || die "--from is after --to"
  f=$(jq -cn --arg a "$d1" --arg b "$d2" '{date:{from:$a,to:$b}}')
  [[ -z "$tz" ]] || f=$(jq -c --arg z "$tz" '.date.timeZone=$z' <<<"$f")
  local p="$pbx"
  if [[ -z "$p" && ${#queues[@]} -gt 0 ]]; then
    p=$(awk -F_ '{print $(NF-1)}' <<<"${queues[0]}")
    [[ "$p" =~ ^[A-Za-z0-9]{4,32}$ ]] || p=""
  fi
  [[ -z "$p" ]] || jset f pbx "$p"
  [[ ${#queues[@]} -eq 0 ]] || jsetj f serviceIds "$(jarr "${queues[@]}")"
  [[ ${#exts[@]} -eq 0 ]] || jsetj f extensions "$(jarr "${exts[@]}")"
  [[ ${#outcomes[@]} -eq 0 ]] || jsetj f outcomes "$(jarr "${outcomes[@]}")"
  [[ ${#reasons[@]} -eq 0 ]] || jsetj f disconnectReasons "$(jarr "${reasons[@]}")"
  [[ ${#weekdays[@]} -eq 0 ]] || jsetj f daysOfWeek "$(jarr "${weekdays[@]}" | jq -c 'map(tonumber)')"
  [[ -z "$hours" ]] || jsetj f hourRange "$(jq -cn --arg a "${hours%-*}" --arg b "${hours#*-}" '{from:$a,to:$b}')"
  [[ -z "$wait_band" ]] || jsetj f waitSecondsRange "$(band_json "$wait_band")"
  [[ -z "$talk_band" ]] || jsetj f talkSecondsRange "$(band_json "$talk_band")"
  [[ -z "$sla" ]] || jsetj f slaSeconds "$sla"
  if [[ ${#queue_slas[@]} -gt 0 ]]; then
    jsetj f serviceSlaSeconds "$(printf '%s\n' "${queue_slas[@]}" | jq -Rsc 'split("\n")[:-1] | map(split("=") | {serviceId: .[0], slaSeconds: (.[1] | tonumber)})')"
  fi
  printf '%s' "$f"
}

report() { # report PATH [extra JSON object merged into the body]
  local body f x="${2:-}"
  [[ -n "$x" ]] || x='{}'
  f=$(filter) || exit 1
  body=$(jq -cn --argjson f "$f" --argjson x "$x" '{filter:$f} + $x')
  wda_call POST "/xcaracal/$1" "$body"
}

ladder() { # the wait or talk band options as a JSON object
  local wk="$1" sk="$2" o='{}'
  [[ -z "$band" ]] || jsetj o "$wk" "$band"
  [[ -z "$steps" ]] || jsetj o "$sk" "$steps"
  printf '%s' "$o"
}

case "$cmd" in
  list)
    r=$(wda_call POST /stream/services '{}')
    jq -c --arg pbx "$pbx" --arg name "$(tr 'A-Z' 'a-z' <<<"$name")" '
      (.services // []) | map(select(($pbx == "" or .pbx == $pbx) and ($name == "" or ((.name // "") | ascii_downcase | contains($name)))))
      | {total: length, pbxs: (group_by(.pbx) | map({(.[0].pbx): length}) | add // {}),
         queues: (sort_by(.pbx, (.name // "")) | map({id, name, pbx, aclGroup: (if (.aclGroup // "") == "" then null else .aclGroup end)} | with_entries(select(.value != null))))}' <<<"$r" ;;
  summary)    report distribution/summary/query ;;
  by-queue)   report distribution/by-service/query ;;
  by-period)
    case "$by" in
      hour|day|week|month) g="$by" ;; weekday) g=dayOfWeek ;; *) die "by-period needs --by hour|day|week|month|weekday" ;;
    esac
    report distribution/by-period/query "$(jq -cn --arg g "$g" '{granularity:$g}')" ;;
  answered)
    if [[ -z "$by" ]]; then report answered/summary/query; else
      case "$by" in
        queue) d=byService ;; agent) d=byAgent ;; user) d=byUser ;; reason) d=byDisconnectReason ;; talk-time) d=byTalkTime ;;
        *) die "answered --by is queue, agent, user, reason or talk-time: $by" ;;
      esac
      o='{}'; [[ "$d" != byTalkTime ]] || o=$(ladder talkBandSeconds talkBandSteps)
      report answered/breakdown/query "$(jq -c --arg d "$d" '. + {dimension:$d}' <<<"$o")"
    fi ;;
  unanswered)
    if [[ -z "$by" ]]; then report unanswered/summary/query; else
      case "$by" in queue) d=byService ;; reason) d=byDisconnectReason ;; *) die "unanswered --by is queue or reason: $by" ;; esac
      report unanswered/breakdown/query "$(jq -cn --arg d "$d" '{dimension:$d}')"
    fi ;;
  service-level)
    [[ ${#positional[@]} -eq 1 && "${positional[0]}" =~ ^(answered|unanswered)$ ]] || die "service-level answered|unanswered"
    report "${positional[0]}/service-level/query" "$(ladder waitBandSeconds waitBandSteps)" ;;
  calls)
    x='{}'
    [[ -z "$limit" ]] || jsetj x limit "$limit"
    [[ -z "$call_id" ]] || jset x callId "$call_id"
    [[ -z "$cursor" ]] || jset x cursor "$cursor"
    all='[]'; next=""; meta='{}'
    for ((i = 1; i <= pages; i++)); do
      r=$(report services/calls/query "$x")
      all=$(jq -c --argjson a "$all" '$a + (.items // [])' <<<"$r")
      meta=$(jq -c '{timeZone, pbx}' <<<"$r")
      next=$(jq -r '.nextCursor // ""' <<<"$r")
      [[ -n "$next" ]] || break
      jset x cursor "$next"
    done
    jq -c --argjson items "$all" --arg next "$next" '. + {count: ($items | length), items: $items} + (if $next == "" then {} else {nextCursor: $next} end)' <<<"$meta" ;;
  events)
    [[ ${#positional[@]} -eq 2 ]] || die "events <callId> <flowIndex> [--queue ID]"
    check_id "the call id" "${positional[0]}"
    fl=$(norm_flow "${positional[1]}")
    q=""; [[ ${#queues[@]} -eq 0 ]] || q="${queues[0]}"
    wda_call GET "/xcaracal/services/calls/${positional[0]}/flows/$fl/events$(qs serviceId "$q")" ;;
  *) usage ;;
esac
