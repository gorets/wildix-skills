#!/usr/bin/env bash
# Shared helpers of the wildix-stream skill. Source it from a section script:
#   . "$(dirname "$0")/lib.sh"
# Needs: bash 3.2+, curl, jq.
#
# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
# Service address: https://eu-1.stream.wildix.com; WILDIX_STREAM_REGION picks another region
# (for example us-1), WILDIX_STREAM_URL replaces the whole address.
set -euo pipefail

STREAM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREAM_BASE="${WILDIX_STREAM_URL:-https://${WILDIX_STREAM_REGION:-eu-1}.stream.wildix.com}"
STREAM_API="$STREAM_BASE/api/v1"
STREAM_UA="wildix-agent-skills/1.1.0"

command -v jq >/dev/null   || { echo "Error: jq is required (brew install jq)" >&2; exit 1; }
command -v curl >/dev/null || { echo "Error: curl is required" >&2; exit 1; }

for _d in "$STREAM_LIB_DIR/../.." "${WILDIX_SKILLS_DIR:-}" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2

die() { echo "Error: $*" >&2; exit 1; }

# A channel id from an id, a "type:id" form or an inbox link (the message part of a link is dropped).
norm_channel() {
  local v="$1"
  v="${v#*/inbox/}"; v="${v%%/*}"; v="${v##*:}"
  [[ -n "$v" ]] || die "empty channel id"
  printf '%s' "$v"
}

# A message id from an id or from an inbox link to the message (the last path segment).
norm_message() {
  local v="$1"
  v="${v##*/}"
  [[ -n "$v" ]] || die "empty message id"
  printf '%s' "$v"
}

# qs name value [name value ...] -> "?name=value&..." with empty values skipped and the rest URL-encoded.
qs() {
  local out="" k v sep="?"
  while [[ $# -ge 2 ]]; do
    k="$1"; v="$2"; shift 2
    [[ -n "$v" ]] || continue
    out="${out}${sep}${k}=$(jq -rn --arg v "$v" '$v|@uri')"
    sep="&"
  done
  printf '%s' "$out"
}

# jset VAR key value   : set a string field in the JSON object kept in VAR
# jsetj VAR key json   : set a field to a JSON value (number, boolean, array, object)
jset()  { local __o; __o=$(jq -c --arg k "$2" --arg v "$3" '.[$k]=$v' <<<"${!1}"); printf -v "$1" '%s' "$__o"; }
jsetj() { local __o; __o=$(jq -c --arg k "$2" --argjson v "$3" '.[$k]=$v' <<<"${!1}"); printf -v "$1" '%s' "$__o"; }

# jarr item ... -> a JSON array of strings (an empty one when there are no items)
jarr() { jq -nc '$ARGS.positional' --args "$@"; }

# stream_call METHOD PATH [JSON_BODY]
# PATH is relative to /api/v1 and may carry a query string. Prints the answer (or {"ok":true} when it is
# empty); on an HTTP error prints the status and the body to stderr and exits 1.
stream_call() {
  local method="$1" path="$2" body="${3:-}" out code
  out=$(mktemp)
  local args=(-sS -o "$out" -w '%{http_code}' -X "$method" -H "User-Agent: $STREAM_UA" -H "Authorization: Bearer $ID_TOKEN" -H "Accept: application/json")
  if [[ -n "$body" ]]; then args+=(-H "Content-Type: application/json" -d "$body"); fi
  code=$(curl "${args[@]}" "$STREAM_API$path") || { rm -f "$out"; die "request failed: $method $path"; }
  if [[ "$code" != 2* ]]; then
    echo "Error: HTTP $code from the stream service ($method $path)" >&2
    cat "$out" >&2; echo >&2
    if grep -q "is not implemented" "$out" 2>/dev/null; then echo "This operation is not implemented in the service yet (a known gap, see SKILL.md). Do not retry; tell the user it is not ready." >&2; fi
    [[ "$code" == 401 ]] && echo "The token was rejected: log in again with the wildix-auth skill. (Only production, $STREAM_BASE, accepts the production login.)" >&2
    rm -f "$out"
    exit 1
  fi
  if [[ -s "$out" ]]; then cat "$out"; echo; else echo '{"ok":true}'; fi
  rm -f "$out"
}

# The stream user id of the logged-in user (cached), found by the e-mail of the token.
me_id() {
  if [[ -z "${_STREAM_ME_ID:-}" ]]; then
    local email body
    email=$(wildix_token_email)
    body=$(jq -nc --arg e "$email" '{query:{emails:[$e]}}')
    _STREAM_ME_ID=$(stream_call POST /users/query "$body" | jq -r '.users[0].id // empty')
    [[ -n "$_STREAM_ME_ID" ]] || die "could not find the stream user of $email"
  fi
  printf '%s' "$_STREAM_ME_ID"
}

# upload_file CHANNEL PATH -> prints the attachment object to put into a message (fsId, name, size, mime)
upload_file() {
  local ch="$1" path="$2" name mime resp fsid url code info
  [[ -f "$path" ]] || die "file not found: $path"
  name=$(basename "$path")
  mime=$(file --mime-type -b "$path" 2>/dev/null || echo application/octet-stream)
  resp=$(stream_call POST "/channels/$ch/files" "$(jq -nc --arg n "$name" '{name:$n}')")
  fsid=$(jq -r '.fsId // empty' <<<"$resp")
  url=$(jq -r '.presignedUploadUrl // empty' <<<"$resp")
  [[ -n "$fsid" && -n "$url" ]] || die "unexpected upload answer: $resp"
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: $mime" --data-binary "@$path" "$url") || die "upload to storage failed"
  [[ "$code" == 2* ]] || die "storage answered HTTP $code"
  info=$(stream_call GET "/channels/$ch/files/$fsid")
  jq -c '.file | {fsId, name, size, mime, width, height, thumbnail} | with_entries(select(.value != null))' <<<"$info"
}

# Reads the text argument; "-" means stdin.
read_text() {
  if [[ "$1" == "-" ]]; then cat; else printf '%s' "$1"; fi
}

# qadd QUERY key value -> QUERY with "key=value" appended (a "?" or "&" as needed); empty values are skipped.
# Use it to repeat a parameter: q=$(qadd "$q" senderIds "$id")
qadd() {
  local s="$1" k="$2" v="$3" sep="&"
  [[ -n "$v" ]] || { printf '%s' "$s"; return; }
  [[ -n "$s" ]] || sep="?"
  printf '%s%s%s=%s' "$s" "$sep" "$k" "$(jq -rn --arg v "$v" '$v|@uri')"
}
