#!/usr/bin/env bash
# Channels of the Wildix stream service. Usage: channels.sh <command> [args]   (see references/channels.openapi.json)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: channels.sh <command> [args]
  list [--section ID] [--filter unread|archived] [--cursor C]
  get <channel>
  query <channelId> [<channelId> ...]            (not implemented yet in the service)
  create-group --subject S [--description D] [--access private|public] [--member USERID]... [--invite EMAIL]... [--id 8-4-4-4-8]
               [--auto-transcribe | --no-auto-transcribe]   conferences in it start transcription by themselves, or not
  direct (--user USERID | --email EMAIL)          get or create the 1:1 channel
  direct-id (--user USERID | --email EMAIL)       only resolve its id
  update <channel> [--subject S] [--description D] [--access A] [--unset FIELD]...   (not implemented yet in the service)
  join <channel>                                 (not implemented yet in the service)
  leave <channel>
  delete <channel> --yes
A channel is an id or an inbox link.
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

case "$cmd" in
  list)
    section=""; filter=""; cursor=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --section) section="$2"; shift 2 ;; --filter) filter="$2"; shift 2 ;; --cursor) cursor="$2"; shift 2 ;; *) usage ;; esac; done
    stream_call GET "/channels$(qs section "$section" filter "$filter" cursor "$cursor")" ;;
  get)
    [[ $# -eq 1 ]] || usage
    stream_call GET "/channels/$(norm_channel "$1")" ;;
  query)
    [[ $# -ge 1 ]] || usage
    ids=(); for c in "$@"; do ids+=("$(norm_channel "$c")"); done
    stream_call POST /channels/query "$(jq -nc --argjson ids "$(jarr "${ids[@]}")" '{query:{ids:$ids}}')" ;;
  create-group)
    subject=""; description=""; access=""; members=(); invites=(); cid=""; transcribe=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --subject) subject="$2"; shift 2 ;; --description) description="$2"; shift 2 ;; --access) access="$2"; shift 2 ;;
      --id) cid="$2"; shift 2 ;;
      --auto-transcribe) transcribe=true; shift ;; --no-auto-transcribe) transcribe=false; shift ;;
      --member) members+=("$2"); shift 2 ;; --invite) invites+=("$2"); shift 2 ;; *) usage ;; esac; done
    [[ -n "$subject" ]] || die "--subject is required"
    # The service takes only ids of the form 8-4-4-4-8 characters in paths, but when none is given it makes
    # a plain 36-character UUID that none of its own calls accepts afterwards. So an id is always sent.
    [[ -n "$cid" ]] || cid=$(python3 -c 'import uuid; print(str(uuid.uuid4())[:-4])')
    [[ "$cid" =~ ^[0-9a-z_]{8}-[0-9a-z_]{4}-[0-9a-z_]{4}-[0-9a-z_]{4}-[0-9a-z_]{8}$ ]] || die "--id must look like 8-4-4-4-8 characters of [0-9a-z_]: $cid"
    body='{}'; jset body channelId "$cid"; jset body subject "$subject"
    [[ -z "$description" ]] || jset body description "$description"
    [[ -z "$access" ]] || jset body access "$access"
    [[ -z "$transcribe" ]] || jsetj body autoTranscribe "$transcribe"
    if [[ ${#members[@]} -gt 0 ]]; then jsetj body members "$(jarr "${members[@]}")"; fi
    if [[ ${#invites[@]} -gt 0 ]]; then
      inv=$(jarr "${invites[@]}" | jq -c 'map({email: .})'); jsetj body membersToInvite "$inv"; fi
    stream_call POST /channels/group "$body" ;;
  direct|direct-id)
    user=""; email=""
    while [[ $# -gt 0 ]]; do case "$1" in --user) user="$2"; shift 2 ;; --email) email="$2"; shift 2 ;; *) usage ;; esac; done
    if [[ -n "$user" ]]; then body=$(jq -nc --arg u "$user" '{memberId:$u}')
    elif [[ -n "$email" ]]; then body=$(jq -nc --arg e "$email" '{memberToInvite:{email:$e}}')
    else die "--user or --email is required"; fi
    if [[ "$cmd" == direct ]]; then stream_call POST /channels/direct/get-or-create "$body"; else stream_call POST /channels/direct/resolve-id "$body"; fi ;;
  update)
    [[ $# -ge 1 ]] || usage
    ch=$(norm_channel "$1"); shift
    set_obj='{}'; unsets=()
    while [[ $# -gt 0 ]]; do case "$1" in
      --subject) jset set_obj subject "$2"; shift 2 ;; --description) jset set_obj description "$2"; shift 2 ;;
      --access) jset set_obj access "$2"; shift 2 ;; --unset) unsets+=("$2"); shift 2 ;; *) usage ;; esac; done
    body=$(jq -nc --argjson s "$set_obj" '{set:$s}')
    if [[ ${#unsets[@]} -gt 0 ]]; then jsetj body unset "$(jarr "${unsets[@]}")"; fi
    [[ "$set_obj" != '{}' || ${#unsets[@]} -gt 0 ]] || die "nothing to change: give --subject, --description, --access or --unset"
    stream_call PATCH "/channels/$ch" "$body" ;;
  join|leave)
    [[ $# -eq 1 ]] || usage
    stream_call POST "/channels/$(norm_channel "$1")/$cmd" '{}' ;;
  delete)
    [[ $# -ge 1 ]] || usage
    ch=$(norm_channel "$1"); shift
    [[ "${1:-}" == "--yes" ]] || die "delete removes the channel for everyone: confirm with the user, then add --yes"
    stream_call DELETE "/channels/$ch" ;;
  *) usage ;;
esac
