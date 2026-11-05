#!/usr/bin/env bash
# Channel members. Usage: members.sh <command> [args]   (exact shapes: references/members.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: members.sh <command> [args]
  list <channel> [--limit 1-100] [--offset 0-1000]
  get <channel> <userId>                 (not implemented yet in the service)
  add <channel> (--user USERID | --invite EMAIL)... [--hide-history]
  remove <channel> <userId>
  read-status <channel>                  who has read up to where (channels with up to 100 members)
A channel is an id or an inbox link.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

case "$cmd" in
  list)
    [[ $# -ge 1 ]] || usage
    ch=$(norm_channel "$1"); shift; limit=""; offset=""
    while [[ $# -gt 0 ]]; do case "$1" in --limit) limit="$2"; shift 2 ;; --offset) offset="$2"; shift 2 ;; *) usage ;; esac; done
    [[ -z "$limit" ]] || check_int --limit "$limit" 1 100
    [[ -z "$offset" ]] || check_int --offset "$offset" 0 1000
    stream_call GET "/channels/$ch/members$(qs limit "$limit" offset "$offset")" ;;
  get)
    [[ $# -eq 2 ]] || usage
    check_id "the user id" "$2"
    stream_call GET "/channels/$(norm_channel "$1")/members/$2" ;;
  add)
    [[ $# -ge 2 ]] || usage
    ch=$(norm_channel "$1"); shift; users=(); invites=(); hide=0
    while [[ $# -gt 0 ]]; do case "$1" in
      --user) users+=("$2"); shift 2 ;; --invite) invites+=("$2"); shift 2 ;; --hide-history) hide=1; shift ;; *) usage ;; esac; done
    [[ ${#users[@]} -gt 0 || ${#invites[@]} -gt 0 ]] || die "give --user USERID or --invite EMAIL"
    body='{}'
    if [[ ${#users[@]} -gt 0 ]]; then jsetj body members "$(jarr "${users[@]}")"; fi
    if [[ ${#invites[@]} -gt 0 ]]; then jsetj body membersToInvite "$(jarr "${invites[@]}" | jq -c 'map({email: .})')"; fi
    [[ $hide -eq 0 ]] || jsetj body hideHistory true
    stream_call PUT "/channels/$ch/members" "$body" ;;
  remove)
    [[ $# -eq 2 ]] || usage
    check_id "the user id" "$2"
    stream_call DELETE "/channels/$(norm_channel "$1")/members/$2" ;;
  read-status)
    [[ $# -eq 1 ]] || usage
    stream_call GET "/channels/$(norm_channel "$1")/read-status" ;;
  *) usage ;;
esac
