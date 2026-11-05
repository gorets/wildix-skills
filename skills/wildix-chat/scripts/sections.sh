#!/usr/bin/env bash
# The user's custom inbox sections. Usage: sections.sh <command> [args]   (references/sections.openapi.json)
# The sections and their counters are in: inbox.sh get
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: sections.sh <command> [args]     (none of these is implemented in the service yet)
  create <sectionId> <name>        sectionId: a-z 0-9 _ - (up to 32), name up to 80
  rename <sectionId> <name>
  delete <sectionId>
  add <channel> <sectionId>        put a channel into a custom section
  remove <channel> <sectionId>     take it out
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift
check_id() { [[ "$1" =~ ^[a-z0-9_-]{1,32}$ ]] || die "sectionId must match [a-z0-9_-] (up to 32): $1"; }

case "$cmd" in
  create)
    [[ $# -eq 2 ]] || usage; check_id "$1"
    stream_call POST /sections "$(jq -nc --arg i "$1" --arg n "$2" '{sectionId:$i,name:$n}')" ;;
  rename)
    [[ $# -eq 2 ]] || usage; check_id "$1"
    stream_call PATCH "/sections/$1" "$(jq -nc --arg n "$2" '{name:$n}')" ;;
  delete)
    [[ $# -eq 1 ]] || usage; check_id "$1"
    stream_call DELETE "/sections/$1" ;;
  add)
    [[ $# -eq 2 ]] || usage; check_id "$2"
    stream_call PUT "/channels/$(norm_channel "$1")/sections/$2" ;;
  remove)
    [[ $# -eq 2 ]] || usage; check_id "$2"
    stream_call DELETE "/channels/$(norm_channel "$1")/sections/$2" ;;
  *) usage ;;
esac
