#!/usr/bin/env bash
# Live calls of the logged-in user on their PBX: list, place, answer, hold, transfer, DTMF, hang up.
# Usage: calls.sh <command> [args]   (exact shapes: references/call-control.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: calls.sh <command> [args]
  me                                     who the calls are made as: extension, name, PBX (no request)
  list                                   the user's current calls: sipCallId, numbers, names, state, seconds
  call <number> [--mobile | --any | --device CONTACT]
                                         place a call: the PBX rings the user's own device first, then dials
                                         <number> when they pick up. Default: the active device (devices.sh)
  answer <callId> [--device CONTACT]     answer a ringing call (on a device that can answer remotely)
  hold <callId> | unhold <callId>
  hangup <callId>
  transfer <callId> <number>             blind transfer to an extension or a phone number
  attended-transfer <callId> <otherCallId>
                                         join the call to another current call of the user (consultation done)
  dtmf <callId> <digits>                 send tones: 0-9, * and #
  show-as <callId> [--name NAME] [--number NUMBER]
                                         change the name and/or number the user's own phone shows for the
                                         other party (the other party sees nothing)
<callId> is the sipCallId from `calls.sh list`. A number is an extension, a phone number or a code like *76.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

# action <path> <json body>: run a call-control action and print {"ok":true,"message":…}
action() { pbx_call POST "$1" "$2" | jq -c '{ok: true, message: (.message // .)}'; }

case "$cmd" in
  me)
    [[ $# -eq 0 ]] || usage
    jq -c --arg pbx "$CC_BASE" '{extension: .["custom:pbx_user_extension"], name, email, role: .["custom:pbx_user_role"], license: .["custom:pbx_license"], pbx: $pbx}' <<<"$CC_CLAIMS" ;;
  list)
    [[ $# -eq 0 ]] || usage
    pbx_call GET /list-calls/ ;;
  call)
    [[ $# -ge 1 ]] || usage
    num=$(norm_number "$1"); shift
    body=$(jq -nc --arg d "$num" '{destination: $d}')
    mode=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --mobile) mode=mobility; jset body callType mobility; shift ;;
      --any) mode=any; jset body callType any; shift ;;
      --device) [[ $# -ge 2 ]] || usage; check_contact "$2"; mode=device; jset body callType device; jset body deviceContact "$2"; shift 2 ;;
      *) usage ;; esac; done
    if [[ -z "$mode" ]]; then
      # With no active device the PBX takes the first registered one, which may be the SIP watcher of this skill
      # (it turns every call down). Pick the device here: the active one, else the first real one.
      dev=$(pbx_call GET /list-devices/ | jq -r '[.devices[]? | select(.userAgent != "wildix-agent-skills watcher")] | ((map(select(.active)) + .)[0].contact) // empty')
      [[ -n "$dev" ]] || die "no device of this user is online to place the call from: open x-bees or a Wildix phone, or call through the mobile (--mobile)"
      jset body deviceContact "$dev"
    fi
    action /make-call/ "$body" ;;
  answer)
    [[ $# -ge 1 ]] || usage
    check_call_id "$1"; body=$(jq -nc --arg c "$1" '{sipCallId: $c}'); shift
    while [[ $# -gt 0 ]]; do case "$1" in
      --device) [[ $# -ge 2 ]] || usage; check_contact "$2"; jset body deviceContact "$2"; shift 2 ;;
      *) usage ;; esac; done
    action /answer/ "$body" ;;
  hold|unhold|hangup)
    [[ $# -eq 1 ]] || usage
    check_call_id "$1"
    action "/$cmd/" "$(jq -nc --arg c "$1" '{sipCallId: $c}')" ;;
  transfer)
    [[ $# -eq 2 ]] || usage
    check_call_id "$1"; num=$(norm_number "$2")
    action /blind-transfer/ "$(jq -nc --arg c "$1" --arg d "$num" '{sipCallId: $c, destination: $d}')" ;;
  attended-transfer)
    [[ $# -eq 2 ]] || usage
    check_call_id "$1"; check_call_id "$2"
    [[ "$1" != "$2" ]] || die "a call cannot be transferred to itself"
    action /attendant-transfer/ "$(jq -nc --arg c "$1" --arg d "$2" '{sipCallId: $c, destination: $d}')" ;;
  dtmf)
    [[ $# -eq 2 ]] || usage
    check_call_id "$1"
    [[ "$2" =~ ^[0-9*#]+$ ]] || die "DTMF digits are 0-9, * and #: $2"
    # The PBX takes at most 10 digits per request: longer sequences go in parts, in order.
    rest="$2"; out=""
    while [[ -n "$rest" ]]; do
      out=$(action /dtmf/ "$(jq -nc --arg c "$1" --arg d "${rest:0:10}" '{sipCallId: $c, digits: $d}')")
      rest="${rest:10}"
    done
    printf '%s\n' "$out" ;;
  show-as)
    [[ $# -ge 2 ]] || usage
    check_call_id "$1"; body=$(jq -nc --arg c "$1" '{sipCallId: $c}'); shift
    while [[ $# -gt 0 ]]; do case "$1" in
      --name) [[ $# -ge 2 && ${#2} -le 100 && -n "$2" ]] || die "--name takes 1 to 100 characters"; jset body name "$2"; shift 2 ;;
      --number) [[ $# -ge 2 ]] || usage; jset body number "$(norm_number "$2")"; shift 2 ;;
      *) usage ;; esac; done
    action /update-contact-info/ "$body" ;;
  *) usage ;;
esac
