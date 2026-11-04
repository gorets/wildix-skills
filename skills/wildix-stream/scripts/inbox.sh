#!/usr/bin/env bash
# The user's inbox: unread, pin, mute, hide. Usage: inbox.sh <command> [args]   (references/inbox.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: inbox.sh <command> [args]
  get                                          recent channels with the user's state, plus the section counters
  read <channel> [--message MESSAGE]           mark read up to the latest (or up to a message)
  unread <channel> [--message MESSAGE] [--force]
  mute <channel> [--until ISO8601] | unmute <channel>
  pin <channel> | unpin <channel>
  hide <channel> | show <channel>              archive or restore it for the user
A channel is an id or an inbox link.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

case "$cmd" in
  get)
    [[ $# -eq 0 ]] || usage
    stream_call GET /inbox ;;
  read|unread)
    [[ $# -ge 1 ]] || usage
    ch=$(norm_channel "$1"); shift; msg=""; force=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --message) msg="$(norm_message "$2")"; shift 2 ;; --force) force="true"; shift ;; *) usage ;; esac; done
    body='{}'; [[ -z "$msg" ]] || jset body messageId "$msg"
    if [[ "$cmd" == read ]]; then stream_call POST "/channels/$ch/read" "$body"
    else stream_call PUT "/channels/$ch/unread$(qs force "$force")" "$body"; fi ;;
  mute)
    [[ $# -ge 1 ]] || usage
    ch=$(norm_channel "$1"); shift; until=""
    while [[ $# -gt 0 ]]; do case "$1" in --until) until="$2"; shift 2 ;; *) usage ;; esac; done
    body='{}'; [[ -z "$until" ]] || jset body mutedUntil "$until"
    stream_call POST "/channels/$ch/mute" "$body" ;;
  unmute)
    [[ $# -eq 1 ]] || usage
    stream_call DELETE "/channels/$(norm_channel "$1")/mute" ;;
  pin)
    [[ $# -eq 1 ]] || usage
    stream_call POST "/channels/$(norm_channel "$1")/pin" '{}' ;;
  unpin)
    [[ $# -eq 1 ]] || usage
    stream_call DELETE "/channels/$(norm_channel "$1")/pin" ;;
  hide|show)
    [[ $# -eq 1 ]] || usage
    stream_call POST "/channels/$(norm_channel "$1")/$cmd" '{}' ;;
  *) usage ;;
esac
