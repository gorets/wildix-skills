#!/usr/bin/env bash
# Shared helpers of the wildix-calls-history skill. Source it from a section script:
#   . "$(dirname "$0")/lib.sh"
# Needs: bash 3.2+, curl, jq.
#
# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
# Service address: https://wda.wildix.com (WDA History and WDA Insights). It must be https://<host>.wildix.com:
# the token is only ever sent there (WILDIX_WDA_URL names another Wildix host, WILDIX_ALLOW_CUSTOM_URL=1 lifts
# the rule for tests against a local server).
set -euo pipefail

WDA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WDA_BASE="${WILDIX_WDA_URL:-https://wda.wildix.com}"
if [[ "${WILDIX_ALLOW_CUSTOM_URL:-}" != 1 ]]; then
  [[ "$WDA_BASE" =~ ^https://[a-z0-9-]+(\.[a-z0-9-]+)*\.wildix\.com(:[0-9]+)?$ ]] || { echo "Error: the service address must be https://<host>.wildix.com, got: $WDA_BASE" >&2; exit 1; }
fi
WDA_API="$WDA_BASE/v2"
WDA_UA="wildix-agent-skills"

command -v jq >/dev/null   || { echo "Error: jq is required (brew install jq)" >&2; exit 1; }
command -v curl >/dev/null || { echo "Error: curl is required" >&2; exit 1; }

for _d in "$WDA_LIB_DIR/../.." "${WILDIX_SKILLS_DIR:-}" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
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

# A conference id from an id or from a link (the last path segment: .../insights/conferences/<id>).
norm_conference() {
  local v="$1"
  v="${v%%[?#]*}"; v="${v%/}"; v="${v##*/}"
  [[ "$v" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && "$v" != *..* && "$v" != conferences ]] || die "not a conference id: $1"
  printf '%s' "$v"
}

# A call is a call id plus a flow index (a call that was transferred has several flows; the first is 0).
norm_flow() {
  local v="${1:-0}"
  [[ "$v" =~ ^[0-9]+$ ]] || die "the flow index must be a number: $v"
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

# jset VAR key value  : set a string field in the JSON object kept in VAR
# jsetj VAR key json  : set a field to a JSON value (number, boolean, array, object)
jset()  { local __o; __o=$(jq -c --arg k "$2" --arg v "$3" '.[$k]=$v' <<<"${!1}"); printf -v "$1" '%s' "$__o"; }
jsetj() { local __o; __o=$(jq -c --arg k "$2" --argjson v "$3" '.[$k]=$v' <<<"${!1}"); printf -v "$1" '%s' "$__o"; }
# (built from NUL-separated input: `jq --args` would take a value that starts with "-" for an option)
jarr()  { if [[ $# -eq 0 ]]; then echo '[]'; else printf '%s\0' "$@" | jq -Rsc 'split("\u0000")[:-1]'; fi; }

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

# The Authorization header goes to curl through a config file on a descriptor, never through argv, where every
# process of the machine could read it with `ps`.
# wda_call METHOD PATH [JSON_BODY]
# PATH is relative to /v2 and may carry a query string. Prints the answer (or {"ok":true} when it is empty);
# on an HTTP error prints the status and the body to stderr and exits 1.
# With WDA_SOFT=1 a 404 is not an error: nothing is printed and the function returns 4, so the caller can say
# "there is none". Call it as:  rc=0; r=$(WDA_SOFT=1 wda_call GET /x) || rc=$?
wda_call() {
  local method="$1" path="$2" body="${3:-}" out code
  check_path "$path"
  out=$(mktemp)
  local args=(-sS --connect-timeout 10 --max-time 60 -o "$out" -w '%{http_code}' -X "$method" -H "User-Agent: $WDA_UA" -H "Accept: application/json")
  [[ "${WILDIX_ALLOW_CUSTOM_URL:-}" == 1 ]] || args+=(--proto '=https')
  if [[ -n "$body" ]]; then args+=(-H "Content-Type: application/json" -d "$body"); fi
  code=$(curl "${args[@]}" -K <(printf 'header = "Authorization: Bearer %s"\n' "$ID_TOKEN") "$WDA_API$path") || { rm -f "$out"; die "request failed: $method $path"; }
  if [[ "$code" != 2* ]]; then
    if [[ "${WDA_SOFT:-}" == 1 && "$code" == 404 ]]; then rm -f "$out"; return 4; fi
    echo "Error: HTTP $code from WDA ($method $path)" >&2
    cat "$out" >&2; echo >&2
    [[ "$code" == 401 ]] && echo "The token was rejected: log in again with the wildix-auth skill." >&2
    [[ "$code" == 403 ]] && echo "The login has no access to this record (a meeting or call of other people, or a role without the right)." >&2
    rm -f "$out"
    exit 1
  fi
  if [[ -s "$out" ]]; then cat "$out"; echo; else echo '{"ok":true}'; fi
  rm -f "$out"
}

# A transcript is confidential: the files and folders this skill creates are private (umask 077), and an
# existing file is replaced only when it is a transcript this skill wrote for the same conference (its second
# line is "# conferenceId: <id>"). Anything else stays untouched: the path may have come from fetched text.
check_out_path() {
  local f="$1" id="${2:-}"
  [[ -n "$f" ]] || die "empty output path"
  if [[ -e "$f" ]]; then
    [[ -n "$id" && "$(sed -n 2p -- "$f" 2>/dev/null)" == "# conferenceId: $id" ]] \
      || die "$f exists: choose another path (nothing was overwritten)"
  fi
}
