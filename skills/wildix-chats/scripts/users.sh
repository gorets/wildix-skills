#!/usr/bin/env bash
# Users of the directory. Usage: users.sh <command> [args]   (references/users.openapi.json; search by name: search.sh users)
. "$(dirname "$0")/lib.sh"

usage() { cat >&2 <<'U'
Usage: users.sh <command> [args]
  me                                                   the logged-in user
  query [--id USERID]... [--email EMAIL]... [--phone PHONE]...   exact lookup, up to the users visible to you
For a search by name, use: search.sh users <query>
U
  exit 1; }

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift

case "$cmd" in
  me)
    [[ $# -eq 0 ]] || usage
    email=$(wildix_token_email); [[ -n "$email" ]] || die "the token carries no e-mail"
    stream_call POST /users/query "$(jq -nc --arg e "$email" '{query:{emails:[$e]}}')" | jq -c '.users[0]' ;;
  query)
    ids=(); emails=(); phones=()
    while [[ $# -gt 0 ]]; do case "$1" in
      --id) ids+=("$2"); shift 2 ;; --email) emails+=("$2"); shift 2 ;; --phone) phones+=("$2"); shift 2 ;; *) usage ;; esac; done
    q='{}'
    if [[ ${#ids[@]} -gt 0 ]]; then jsetj q ids "$(jarr "${ids[@]}")"; fi
    if [[ ${#emails[@]} -gt 0 ]]; then jsetj q emails "$(jarr "${emails[@]}")"; fi
    if [[ ${#phones[@]} -gt 0 ]]; then jsetj q phones "$(jarr "${phones[@]}")"; fi
    [[ "$q" != '{}' ]] || die "give --id, --email or --phone"
    stream_call POST /users/query "$(jq -nc --argjson q "$q" '{query:$q}')" ;;
  *) usage ;;
esac
