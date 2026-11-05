#!/usr/bin/env bash
# Shared helpers of the wildix-conversation-history skill. Source it from a section script:
#   . "$(dirname "$0")/lib.sh"
# Needs: bash 3.2+, curl, jq.
#
# Authentication belongs to the wildix-auth skill: it loads ID_TOKEN without ever printing it.
# Service address: https://wda.wildix.com (WDA History and WDA Insights); WILDIX_WDA_URL replaces it.
set -euo pipefail

WDA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WDA_BASE="${WILDIX_WDA_URL:-https://wda.wildix.com}"
WDA_API="$WDA_BASE/v2"
WDA_UA="wildix-agent-skills/1.1.0"

command -v jq >/dev/null   || { echo "Error: jq is required (brew install jq)" >&2; exit 1; }
command -v curl >/dev/null || { echo "Error: curl is required" >&2; exit 1; }

for _d in "$WDA_LIB_DIR/../.." "${WILDIX_SKILLS_DIR:-}" "$HOME/.agents/skills" "$HOME/.claude/skills"; do
  [ -f "$_d/wildix-auth/scripts/load-token.sh" ] && { . "$_d/wildix-auth/scripts/load-token.sh"; break; } || true
done
command -v wildix_require_token >/dev/null || { echo "Error: the wildix-auth skill is not installed. Ask the user to run: npx skills add gorets/wildix-skills --s wildix-auth" >&2; exit 2; }
wildix_require_token || exit 2

die() { echo "Error: $*" >&2; exit 1; }

# A conference id from an id or from a link (the last path segment: .../insights/conferences/<id>).
norm_conference() {
  local v="$1"
  v="${v%%\?*}"; v="${v%/}"; v="${v##*/}"
  [[ -n "$v" ]] || die "empty conference id"
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
jarr()  { jq -nc '$ARGS.positional' --args "$@"; }

# wda_call METHOD PATH [JSON_BODY]
# PATH is relative to /v2 and may carry a query string. Prints the answer (or {"ok":true} when it is empty);
# on an HTTP error prints the status and the body to stderr and exits 1.
# With WDA_SOFT=1 a 404 is not an error: nothing is printed and the function returns 4, so the caller can say
# "there is none". Call it as:  rc=0; r=$(WDA_SOFT=1 wda_call GET /x) || rc=$?
wda_call() {
  local method="$1" path="$2" body="${3:-}" out code
  out=$(mktemp)
  local args=(-sS -o "$out" -w '%{http_code}' -X "$method" -H "User-Agent: $WDA_UA" -H "Authorization: Bearer $ID_TOKEN" -H "Accept: application/json")
  if [[ -n "$body" ]]; then args+=(-H "Content-Type: application/json" -d "$body"); fi
  code=$(curl "${args[@]}" "$WDA_API$path") || { rm -f "$out"; die "request failed: $method $path"; }
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
