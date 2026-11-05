#!/usr/bin/env bash
# Shared helpers of the wildix-chats skill. Source it from a section script:
#   . "$(dirname "$0")/lib.sh"
# Needs: bash 3.2+, curl, jq.
#
# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
# Service address: https://eu-1.stream.wildix.com; WILDIX_STREAM_REGION picks another region. The address
# must be https://<host>.wildix.com: the token is only ever sent there (WILDIX_ALLOW_CUSTOM_URL=1 lifts this
# for tests against a local server).
set -euo pipefail

STREAM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREAM_BASE="${WILDIX_STREAM_URL:-https://${WILDIX_STREAM_REGION:-eu-1}.stream.wildix.com}"
if [[ "${WILDIX_ALLOW_CUSTOM_URL:-}" != 1 ]]; then
  [[ "$STREAM_BASE" =~ ^https://[a-z0-9-]+(\.[a-z0-9-]+)*\.wildix\.com(:[0-9]+)?$ ]] || { echo "Error: the service address must be https://<host>.wildix.com, got: $STREAM_BASE" >&2; exit 1; }
fi
STREAM_API="$STREAM_BASE/api/v1"
STREAM_UA="wildix-agent-skills"

command -v jq >/dev/null   || { echo "Error: jq is required (brew install jq)" >&2; exit 1; }
command -v curl >/dev/null || { echo "Error: curl is required" >&2; exit 1; }

for _d in "$STREAM_LIB_DIR/../.." "${WILDIX_SKILLS_DIR:-}" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2

die() { echo "Error: $*" >&2; exit 1; }

# check_int NAME VALUE MIN MAX: stops with a clear message unless VALUE is a whole number from MIN to MAX
# (the service refuses anything else with a 400 that names a path, which tells an agent little).
check_int() { [[ "$2" =~ ^[0-9]{1,12}$ && "$((10#$2))" -ge "$3" && "$((10#$2))" -le "$4" ]] || die "$1 must be a whole number from $3 to $4: $2"; }

# check_id NAME VALUE: an id that goes into a request path (a user id, a file id, a call id): id characters
# only, never "/", "?", "#", ".." or an empty value.
check_id() { [[ "$2" =~ ^[A-Za-z0-9_+][A-Za-z0-9_.:+-]*$ && "$2" != *..* ]] || die "$1 is not a valid id: $2"; }

# A channel id from an id, a "type:id" form or an inbox link (the message part of a link is dropped).
norm_channel() {
  local v="$1"
  v="${v%%[?#]*}"; v="${v#*/inbox/}"; v="${v%%/*}"; v="${v##*:}"
  [[ "$v" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && "$v" != *..* ]] || die "not a channel id: $1"
  printf '%s' "$v"
}

# A message id from an id or from an inbox link to the message (the last path segment).
norm_message() {
  local v="$1"
  v="${v%%[?#]*}"; v="${v%/}"; v="${v##*/}"
  [[ "$v" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && "$v" != *..* ]] || die "not a message id: $1"
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
# (built from NUL-separated input: `jq --args` would take a value that starts with "-" for an option)
jarr() { if [[ $# -eq 0 ]]; then echo '[]'; else printf '%s\0' "$@" | jq -Rsc 'split("\u0000")[:-1]'; fi; }

# check_path PATH: every segment of a request path is an id or a fixed word. Nothing empty, no "." or "..",
# no "/", "?" or "#" smuggled into an id: an id that came from fetched data must not rewrite the path.
check_path() {
  local p="${1%%\?*}" seg
  [[ "$p" == /* && "$p" != *//* && "$p" != */ ]] || die "an id is empty in the request path: $1"
  local IFS=/
  for seg in ${p#/}; do
    [[ "$seg" =~ ^[A-Za-z0-9_+][A-Za-z0-9_.:+-]*$ && "$seg" != *..* ]] || die "an id is not safe in the request path: $1"
  done
}

# curl_auth: the Authorization header goes to curl through a config file on a descriptor, never through argv,
# where every process of the machine could read it with `ps`.
# stream_call METHOD PATH [JSON_BODY]
# PATH is relative to /api/v1 and may carry a query string. Prints the answer (or {"ok":true} when it is
# empty); on an HTTP error prints the status and the body to stderr and exits 1.
stream_call() {
  local method="$1" path="$2" body="${3:-}" out code
  check_path "$path"
  out=$(mktemp)
  local args=(-sS --connect-timeout 10 --max-time 60 -o "$out" -w '%{http_code}' -X "$method" -H "User-Agent: $STREAM_UA" -H "Accept: application/json")
  [[ "${WILDIX_ALLOW_CUSTOM_URL:-}" == 1 ]] || args+=(--proto '=https')
  if [[ -n "$body" ]]; then args+=(-H "Content-Type: application/json" -d "$body"); fi
  code=$(curl "${args[@]}" -K <(printf 'header = "Authorization: Bearer %s"\n' "$ID_TOKEN") "$STREAM_API$path") || { rm -f "$out"; die "request failed: $method $path"; }
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
    [[ -n "$email" ]] || die "the token carries no e-mail"
    body=$(jq -nc --arg e "$email" '{query:{emails:[$e]}}')
    _STREAM_ME_ID=$(stream_call POST /users/query "$body" | jq -r '.users[0].id // empty')
    [[ -n "$_STREAM_ME_ID" ]] || die "could not find the stream user of $email"
  fi
  printf '%s' "$_STREAM_ME_ID"
}

# upload_file CHANNEL PATH -> prints the attachment object to put into a message (fsId, name, size, mime)
# A file is refused when it lies where credentials live: an agent that was talked into attaching one would
# send it out of the machine. The user can copy the file elsewhere if they really mean it.
refuse_secret_path() {
  local f="$1" dir real base cfg
  dir=$(cd "$(dirname -- "$f")" 2>/dev/null && pwd -P) || die "cannot read the folder of: $f"
  base=$(basename -- "$f"); real="$dir/$base"
  cfg=$(cd "$(wildix_config_dir)" 2>/dev/null && pwd -P || echo "$HOME/.wildix")
  case "$real" in
    "$cfg"/*|"$HOME"/.wildix/*|"$HOME"/.ssh/*|"$HOME"/.aws/*|"$HOME"/.gnupg/*|"$HOME"/.config/gcloud/*|"$HOME"/.kube/*|"$HOME"/.docker/*|"$HOME"/.claude/*|"$HOME"/.agents/*|"$HOME"/.netrc|"$HOME"/.npmrc)
      die "refusing to attach a file from a credentials folder: $f" ;;
  esac
  case "$base" in
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|id_rsa*|id_ed25519*|*.kdbx|credentials*.json|*secret*|*.token)
      die "refusing to attach what looks like a secret: $base" ;;
  esac
}

upload_file() {
  local ch="$1" path="$2" name mime resp fsid url code info
  [[ -f "$path" ]] || die "file not found: $path"
  refuse_secret_path "$path"
  name=$(basename -- "$path")
  mime=$(file --mime-type -b "$path" 2>/dev/null || echo application/octet-stream)
  resp=$(stream_call POST "/channels/$ch/files" "$(jq -nc --arg n "$name" '{name:$n}')")
  fsid=$(jq -r '.fsId // empty' <<<"$resp")
  url=$(jq -r '.presignedUploadUrl // empty' <<<"$resp")
  [[ -n "$fsid" && -n "$url" ]] || die "unexpected upload answer: $resp"
  code=$(curl -sS --connect-timeout 10 --max-time 600 --proto '=https' -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: $mime" --data-binary "@$path" "$url") || die "upload to storage failed"
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
