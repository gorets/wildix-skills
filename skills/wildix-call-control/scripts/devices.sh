#!/usr/bin/env bash
# The devices of the logged-in user on their PBX, and which of them rings and places calls.
# Usage: devices.sh <command> [args]   (exact shapes: references/call-control.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: devices.sh <command> [args]
  list                     the user's registered devices: userAgent, contact, active
  use <contact>            make this registered device the active one (the one that places the user's calls)
  use --mobile             mobility mode: calls go through the user's mobile number
  use --any                ring all the user's devices
A device is named by its SIP contact (sip:…), as `devices.sh list` gives it.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

case "$cmd" in
  list)
    [[ $# -eq 0 ]] || usage
    # The SIP watcher of this skill (sip.sh) is a registered device too: it is marked, so it is never picked to ring.
    pbx_call GET /list-devices/ | jq -c '.devices |= map(if .userAgent == "wildix-agent-skills watcher" then . + {watcher: true} else . end)' ;;
  use)
    [[ $# -eq 1 ]] || usage
    case "$1" in
      --mobile) body='{"deviceType":"mobility"}' ;;
      --any) body='{"deviceType":"any"}' ;;
      --*) usage ;;
      *)
        check_contact "$1"
        # The PBX wants the device's user agent too: take it from the registration of that contact.
        ua=$(pbx_call GET /list-devices/ | jq -r --arg c "$1" '[.devices[]? | select(.contact == $c) | .userAgent][0] // empty')
        [[ -n "$ua" ]] || die "no registered device of this user has the contact $1 (see: devices.sh list)"
        [[ "$ua" != "wildix-agent-skills watcher" ]] || die "this is the SIP watcher of this skill, not a phone: it cannot carry a call"
        body=$(jq -nc --arg c "$1" --arg u "$ua" '{deviceType: "device", contact: $c, userAgent: $u}') ;;
    esac
    pbx_call PUT /set-active-device/ "$body" | jq -c '{ok: true, message: (.message // .)}' ;;
  *) usage ;;
esac
