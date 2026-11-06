#!/usr/bin/env bash
# Shared helpers of the wildix-call-control skill. Source it from a script:
#   . "$(dirname "$0")/lib.sh"
# Needs: bash 3.2+, curl, jq.
#
# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
# The PBX: the x-bees login token names the user's PBX itself (claims custom:pbx_domain and custom:pbx_port), and
# the PBX accepts that same token. The token is only ever sent to that PBX. WILDIX_PBX_URL overrides the address
# only together with WILDIX_ALLOW_CUSTOM_URL=1 (tests against a local server).
set -euo pipefail

CC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_UA="wildix-agent-skills"

command -v jq >/dev/null   || { echo "Error: jq is required (brew install jq)" >&2; exit 1; }
command -v curl >/dev/null || { echo "Error: curl is required" >&2; exit 1; }

for _d in "$CC_LIB_DIR/../.." "${WILDIX_SKILLS_DIR:-}" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2

die() { echo "Error: $*" >&2; exit 1; }

# The claims of the login token as JSON. The token goes to jq on stdin, never on a command line.
token_claims() {
  printf '%s' "$ID_TOKEN" | jq -Rc 'split(".")[1] | gsub("-"; "+") | gsub("_"; "/") | . + ("=" * ((4 - length % 4) % 4)) | @base64d | fromjson' 2>/dev/null \
    || die "the login token could not be read: log in again with the wildix-auth skill"
}

CC_CLAIMS=$(token_claims)
claim() { jq -r --arg k "$1" '.[$k] // empty' <<<"$CC_CLAIMS"; }

if [[ -n "${WILDIX_PBX_URL:-}" ]]; then
  [[ "${WILDIX_ALLOW_CUSTOM_URL:-}" == 1 ]] || die "WILDIX_PBX_URL is honoured only with WILDIX_ALLOW_CUSTOM_URL=1 (tests); the PBX comes from the login itself"
  CC_BASE="${WILDIX_PBX_URL%/}"
else
  _host=$(claim custom:pbx_domain); _port=$(claim custom:pbx_port)
  [[ -n "$_host" ]] || die "this login is not linked to a PBX (the token has no custom:pbx_domain): call control needs a PBX user"
  [[ "$_host" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]] || die "the PBX address in the login is not a host name: $_host"
  [[ -z "$_port" || "$_port" =~ ^[0-9]{1,5}$ ]] || die "the PBX port in the login is not a number: $_port"
  CC_BASE="https://$_host"
  [[ -z "$_port" || "$_port" == 443 ]] || CC_BASE="$CC_BASE:$_port"
fi
CC_API="$CC_BASE/api/v2/call-control"

# pbx_call METHOD PATH [JSON_BODY]
# PATH is relative to /api/v2/call-control (e.g. /list-calls/). The PBX wraps answers as {"type":"result","result":X}
# and errors as {"type":"error","reason":…,"code":…}; this prints X, or the reason on stderr and exits 1.
# The Authorization header goes to curl through a config file on a descriptor, never through argv.
pbx_call() {
  local method="$1" path="$2" body="${3:-}" out code reason
  [[ "$path" =~ ^/[a-z-]+/$ ]] || die "not a call-control path: $path"
  out=$(mktemp)
  local args=(-sS --connect-timeout 10 --max-time 30 -o "$out" -w '%{http_code}' -X "$method" -H "User-Agent: $CC_UA" -H "Accept: application/json")
  [[ "${WILDIX_ALLOW_CUSTOM_URL:-}" == 1 ]] || args+=(--proto '=https')
  if [[ -n "$body" ]]; then args+=(-H "Content-Type: application/json" -d "$body"); fi
  code=$(curl "${args[@]}" -K <(printf 'header = "Authorization: Bearer %s"\n' "$ID_TOKEN") "$CC_API$path") || { rm -f "$out"; die "request failed: $method $path (the PBX $CC_BASE did not answer)"; }
  if [[ "$code" != 2* ]] || [[ "$(jq -r '.type // empty' "$out" 2>/dev/null)" == error ]]; then
    reason=$(jq -c 'if .reason then .reason else . end' "$out" 2>/dev/null || head -c 500 "$out")
    rm -f "$out"
    echo "Error: HTTP $code from the PBX ($method $path): $reason" >&2
    case "$code" in
      401) echo "The PBX rejected the login: log in again with the wildix-auth skill. A PBX accepts only the login of its own environment (a production login works only on a production PBX)." >&2 ;;
      403) echo "The PBX does not allow this to this user: an ordinary user controls only their own calls and devices." >&2 ;;
      404) if [[ "$reason" == *"404 Not Found"* ]]; then
             echo "This PBX has no Call Control API: it needs a newer WMS version." >&2
           else
             echo "The PBX does not see this call among the user's current calls: list them again (calls.sh list)." >&2
           fi ;;
      503) echo "The PBX could not reach its call engine: try again in a moment." >&2 ;;
    esac
    exit 1
  fi
  jq -c '.result // .' "$out"
  rm -f "$out"
}

# A SIP call id as list-calls gives it (the PBX checks the same pattern).
check_call_id() {
  [[ "$1" =~ ^[A-Za-z0-9.!%*_\'+~-]+(@[A-Za-z0-9.-]+)?$ && ${#1} -le 100 ]] || die "not a call id (take sipCallId from: calls.sh list): $1"
}

# A number to call or to transfer to: an extension, a phone number, a feature code like *76. Spaces, dashes,
# dots and brackets that people write in phone numbers are dropped; what is left must be +, digits, * and #.
norm_number() {
  local v="$1"
  v="${v//[[:space:]]/}"; v="${v//-/}"; v="${v//./}"; v="${v//(/}"; v="${v//)/}"
  [[ "$v" =~ ^\+?[0-9*#]+$ && ${#v} -le 40 ]] || die "not a phone number or extension: $1"
  printf '%s' "$v"
}

check_contact() {
  [[ "$1" =~ ^sip:[^[:space:]]+$ && ${#1} -le 255 ]] || die "a device is its SIP contact, as devices.sh list gives it (sip:…): $1"
}

# jset VAR key value : set a string field in the JSON object kept in VAR
jset() { local __o; __o=$(jq -c --arg k "$2" --arg v "$3" '.[$k]=$v' <<<"${!1}"); printf -v "$1" '%s' "$__o"; }
